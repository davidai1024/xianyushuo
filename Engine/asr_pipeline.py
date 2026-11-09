"""Local ASR: conservative vocabulary-guided audio re-decoding.
No transcript substitutions or reference text are used by this module.
"""
from __future__ import annotations
import difflib,re,json,hashlib,time
import numpy as np

LATIN=re.compile(r"[A-Za-z]+(?:['’-][A-Za-z]+)*")
CJK=re.compile(r'[\u3400-\u9fff]')

def audio_stats(audio,sr=16000):
    a=np.asarray(audio,dtype=np.float32)
    if a.size==0:return {'peak_dbfs':-120.,'rms_dbfs':-120.,'gain_db':0.}
    peak=float(np.max(np.abs(a)));rms=float(np.sqrt(np.mean(a*a)))
    frames=[float(np.sqrt(np.mean(z*z)))for z in np.array_split(a,max(1,len(a)//320))]
    active=float(np.percentile(frames,90))
    gain=max(0.,min(30.,-20.-20.*np.log10(active+1e-10),20.*np.log10(.9/(peak+1e-10))))
    if rms<10**(-65/20):gain=0.
    return {'peak_dbfs':float(20*np.log10(peak+1e-10)),'rms_dbfs':float(20*np.log10(rms+1e-10)),'gain_db':float(gain)}

def dictionary_echo(text,hints):
    """Detect dictionary-only recitals, then retry the audio without that bias."""
    rest=text.casefold();hits=0
    for word in sorted(set(hints),key=len,reverse=True):
        pattern=re.compile(r'(?<![a-z0-9])'+re.escape(word.casefold())+r'(?![a-z0-9])')
        rest,n=pattern.subn(' ',rest)
        hits+=bool(n)
    return hits>=3 and not any(c.isalnum()for c in rest)

def chinese_and_numbers(text):
    return ''.join(CJK.findall(text)),re.findall(r'\d+(?:[.,]\d+)*',text)

def english_terms(hints):
    return [w for w in hints if re.fullmatch(r"[A-Za-z][A-Za-z0-9 ._'’-]{0,79}",w) and w.casefold()!='openwhispr']

def recognize(model,audio,hints,language=None,*,max_tokens=2048,max_redecode_seconds=12):
    a=np.asarray(audio,dtype=np.float32)
    if not a.size or float(np.max(np.abs(a)))<1e-7:
        return '',{'segments':[],'digital_silence':True}
    spans=[(0,len(a))]
    outputs=[];details=[]
    for start,end in spans:
        clip=a[start:end]
        stats=audio_stats(clip)
        normalized=clip*10**(stats['gain_db']/20)
        budget=max(max_tokens,min(16384,int(len(clip)/16000*14)+512))
        quiet_signal=(len(clip)/16000<=12 and stats['rms_dbfs'] < -40 and stats['rms_dbfs'] > -65 and stats['gain_db'] >= 10 and stats['peak_dbfs']-stats['rms_dbfs']>=12)
        detail={'start_seconds':start/16000,'end_seconds':end/16000,'second_pass':False,**stats,'normalized_first_pass':False,'token_budget':budget}
        def decode(*,samples=None,**kwargs):
            samples=clip if samples is None else samples
            call_words=kwargs.get('hotwords',[])
            detail.setdefault('decoder_calls',[]).append({'hotwords_count':len(call_words),'hotwords_sha256':hashlib.sha256(json.dumps(call_words,ensure_ascii=False,separators=(',',':')).encode()).hexdigest(),'focused_dictionary_prompt':bool(kwargs.get('system_prompt'))})
            record=detail['decoder_calls'][-1]
            # MLX loader exposes bound methods through a wrapper; trace the actual decoder.
            decoder=getattr(model.generate,'__self__',model)
            original_prompt=getattr(decoder,'_build_prompt',None)
            if original_prompt is not None:
                def trace_prompt(num_audio_tokens,language=None,system_prompt=None):
                    context=system_prompt or ''
                    record['effective_prompt_sha256']=hashlib.sha256(context.encode()).hexdigest()
                    record['effective_prompt_characters']=len(context)
                    record['effective_dictionary_terms']=sum(bool(re.search(r'(?<![A-Za-z0-9])'+re.escape(w)+r'(?![A-Za-z0-9])',context,re.I))if re.fullmatch(r'[A-Za-z0-9 ._’\'-]+',w)else w in context for w in hints)
                    return original_prompt(num_audio_tokens,language,system_prompt)
                object.__setattr__(decoder,'_build_prompt',trace_prompt)
            began=time.perf_counter()
            try:result=model.generate(samples,language=language,max_tokens=budget,temperature=0,verbose=False,**kwargs)
            finally:
                record['seconds']=time.perf_counter()-began
                if original_prompt is not None:object.__setattr__(decoder,'_build_prompt',original_prompt)
            used=getattr(result,'generation_tokens',0)
            if used>=budget:
                retry_budget=min(32768,budget*2)
                result=model.generate(samples,language=language,max_tokens=retry_budget,temperature=0,verbose=False,**kwargs)
                detail['token_limit_retry']=retry_budget
                if getattr(result,'generation_tokens',0)>=retry_budget:
                    raise RuntimeError('Transcription output reached its limit; please split this recording instead of using partial text')
            detail['generation_tokens']=getattr(result,'generation_tokens',0)
            return result.text.strip()
        first=decode(hotwords=hints)
        final=first
        # A full personal dictionary can suppress a very short quiet utterance.
        # Retry the ORIGINAL audio without lexical hints; amplification is not
        # required and can turn a letter into a different Chinese homophone.
        # Steady low noise and near-silence do not qualify as quiet speech.
        empty_with_signal=not first and (detail['rms_dbfs']>-40 or quiet_signal)
        if dictionary_echo(first,hints) or empty_with_signal:
            first=decode()
            final=first
            detail['unhinted_fallback']='empty_with_signal'if empty_with_signal else'dictionary_echo'
        terms=english_terms(hints)
        known={w.casefold()for w in hints if re.fullmatch(r"[A-Za-z][A-Za-z0-9 ._'’-]{0,79}",w)}
        tokens=LATIN.findall(first)
        # Gain can turn a correctly heard letter C into Chinese 是. Keep the raw
        # first pass. Only uncertain short English can propose a gain-based retry,
        # and a separate unhinted audio decode must agree without losing a known word.
        if quiet_signal and not CJK.search(first) and 1<len(tokens)<=4 and any(t.casefold()not in known for t in tokens) and any(t.casefold()in known and len(t)>1 for t in tokens):
            gained=decode(samples=normalized,hotwords=hints)
            gained_words=[t.casefold()for t in LATIN.findall(gained)]
            anchors=[t.casefold()for t in tokens if t.casefold()in known]
            if not CJK.search(gained)and gained_words and all(t in known for t in gained_words)and gained_words==anchors:
                unhinted=decode(samples=normalized)
                if not CJK.search(unhinted)and [t.casefold()for t in LATIN.findall(unhinted)]==gained_words:
                    final=gained
                    detail.update(quiet_english_retry=True,quiet_retry_accepted=True)
        unknown=any(t.casefold()not in known for t in tokens)
        metalinguistic=bool(re.search(r'单词|英文|字母|不是|不对|而非',first))and 2<=len(tokens)<=4
        mixed=bool(CJK.search(first))and bool(tokens)and bool(terms)and len(tokens)<=32
        spelled_initialism=len(tokens)>=2 and all(len(token)==1 for token in tokens) and not metalinguistic
        if mixed and spelled_initialism:detail['second_pass_skipped']='spelled_initialism'
        if mixed and (unknown or metalinguistic) and len(clip)/16000>max_redecode_seconds:
            detail['second_pass_skipped']='long_recording'
        if mixed and not spelled_initialism and (unknown or metalinguistic) and len(clip)/16000<=max_redecode_seconds:
            def latin(text):return [x.casefold()for x in LATIN.findall(text)]
            original=latin(first);allowed=set(original)|known
            def safe(text,allow_new=False):
                values=latin(text)
                return chinese_and_numbers(first)==chinese_and_numbers(text)and len(values)==len(original)and (allow_new or all(x in allowed for x in values))
            def key(text):return tuple(latin(text))
            def relevance(word):return max(difflib.SequenceMatcher(None,word.casefold(),t).ratio()for t in original)
            closest=sorted(terms,key=relevance,reverse=True)[:3]
            focused=[w for w in terms if w in closest]
            prompt='以下是音频中可能出现的英文词汇：'+'、'.join(focused)+'。请保留英文拼写，不要翻译。'
            focused_text=decode(samples=normalized,system_prompt=prompt)
            detail.update(second_pass=True,accepted=False,focused_dictionary_count=len(focused),focused_dictionary_sha256=hashlib.sha256(json.dumps(focused,ensure_ascii=False,separators=(',',':')).encode()).hexdigest())
            candidate=latin(focused_text)
            old_hits=sum(x in known for x in original);new_hits=sum(x in known for x in candidate)
            anchors_preserved=all(a==b for a,b in zip(original,candidate)if a in known)
            if safe(focused_text)and new_hits>old_hits and anchors_preserved:
                final=focused_text;detail.update(accepted=True,acceptance='focused_vocabulary_anchored')
            elif safe(focused_text,allow_new=True)and key(focused_text)!=tuple(original):
                # A known word can only change after two distinct audio decodes agree.
                confirmation=decode(samples=normalized,system_prompt='English vocabulary: '+', '.join(focused)+'. Chinese and English mixed speech.')
                if safe(confirmation,allow_new=True)and key(confirmation)==key(focused_text):
                    final=focused_text;detail.update(accepted=True,acceptance='two_contexts_agree')
            if not detail['accepted']and metalinguistic:
                # Broader context occasionally rescues a confusable known word, but
                # only an unhinted audio decode may confirm it. No string replacement.
                broad=decode(samples=normalized,hotwords=hints,system_prompt='中英混合语音，英文保持英文拼写，不翻译。以下仅是可能出现的词，不要复述词表：')
                plain=decode(samples=normalized)
                if safe(plain)and key(plain)!=tuple(original):
                    if safe(broad)and key(plain)==key(broad):
                        final=broad;detail.update(accepted=True,acceptance='context_and_unhinted_agree')
                    else:
                        changed={a for a,b in zip(original,latin(plain))if a!=b}
                        reduced=[w for w in focused if w.casefold()not in changed]
                        if reduced:
                            neutral=decode(samples=normalized,hotwords=reduced)
                            if safe(neutral)and key(neutral)==key(plain):
                                final=plain;detail.update(accepted=True,acceptance='unhinted_and_dropout_agree')
        # Spoken letter qualifiers describe the desired letter/case, not prose.
        letter=re.fullmatch(r'(capital|uppercase|lowercase|small)\s+(?:letter\s+)?([A-Za-z])[.!。\s]*',final,re.I)
        if letter:
            final=letter.group(2).lower()if letter.group(1).casefold()in {'lowercase','small'}else letter.group(2).upper()
            detail['spoken_letter_format']=True
        # Long dictionaries can suppress very quiet short speech. The full
        # dictionary always receives the first decode. A bounded prefix, keeping
        # the user's established terms first, is an additional acoustic check;
        # never displace a newly recognized dictionary word with this subset.
        quiet_review=(len(clip)/16000<=30 and -75 < stats['rms_dbfs'] < -40 and stats['peak_dbfs']>-60 and (stats['gain_db']>=10 or stats['rms_dbfs']<=-65) and stats['peak_dbfs']-stats['rms_dbfs']>=12)
        if len(hints)>12 and ((quiet_review and (not first.strip() or empty_with_signal or len(clip)/16000>12)) or (len(clip)/16000<=12 and metalinguistic)):
            compact=hints[:12]
            fresh={w.casefold() for w in hints[12:]}
            fresh_anchors=[w for w in fresh if re.search(r'(?<![A-Za-z0-9])'+re.escape(w)+r'(?![A-Za-z0-9])',final,re.I)]
            if not fresh_anchors:
                alternative,review=recognize(model,clip,compact,language,max_tokens=max_tokens,max_redecode_seconds=max_redecode_seconds)
                accepted=bool(alternative.strip()) and (not final.strip() or chinese_and_numbers(final)==chinese_and_numbers(alternative))
                detail['compact_dictionary_review']={'dictionary_count':len(compact),'dictionary_sha256':hashlib.sha256(json.dumps(compact,ensure_ascii=False,separators=(',',':')).encode()).hexdigest(),'asr':review,'accepted':accepted}
                if accepted:final=alternative
        outputs.append(final);details.append(detail)
    return ' '.join(x for x in outputs if x).strip(),{'segments':details}
