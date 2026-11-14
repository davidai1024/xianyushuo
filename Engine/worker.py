"""Local dictation worker with optional DeepSeek text editing."""
from __future__ import annotations
import os
os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', TOKENIZERS_PARALLELISM='false')
import sys, json, time, hashlib, math, re, gc, select, threading
from pathlib import Path
from contextlib import redirect_stdout
WIRE=sys.stdout
MODELS={}
ASR_WARM=False
EDITOR_WARM=False
AUDIO_WARM=False

def send(value):
    WIRE.write(json.dumps(value,ensure_ascii=False)+'\n');WIRE.flush()

def vocabulary(value):
    if not isinstance(value,list) or len(value)>128:raise ValueError('个人词表最多128项，请导出或精简后重试。')
    words=[]
    for w in value:
        if not isinstance(w,str) or not w.strip() or len(w)>80 or '\n' in w:raise ValueError('词表包含无效条目。')
        if w.strip() not in words:words.append(w.strip())
    return words

def digest(words):return hashlib.sha256(json.dumps(words,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()

def load(role,root):
    if role not in MODELS:
        names={'asr':'Qwen3-ASR-1.7B-8bit','cleanup':'Qwen3-1.7B-4bit','mt':'Hy-MT2-1.8B-4bit'}
        folder=Path(root)/names[role]
        if not folder.is_dir():raise ValueError('缺少本地模型：'+names[role])
        if role=='asr':
            from mlx_audio.stt.utils import load as loader
        else:
            from mlx_lm import load as loader
        MODELS[role]=loader(str(folder))
    return MODELS[role]

def warm_audio():
    """Load CPU audio dependencies before reporting readiness, without mic/files."""
    global AUDIO_WARM
    if AUDIO_WARM:return
    import io,numpy as np,soundfile as sf
    from scipy.signal import resample_poly
    # Exercise actual decode and common capture-rate resampling in memory.
    sample=np.zeros(2400,dtype=np.float32)
    wav=io.BytesIO();sf.write(wav,sample,24000,format='WAV',subtype='PCM_16');wav.seek(0)
    decoded,rate=sf.read(wav,dtype='float32',always_2d=True)
    resample_poly(decoded.mean(axis=1),2,3)
    resample_poly(sample,1,3)
    resample_poly(sample,160,441)
    AUDIO_WARM=True

def local_editor_requested(job):
    return job.get('cleanup','light') != 'none' and job.get('cleanup_provider') != 'deepseek'

def release_editor():
    """Drop weights and their instruction caches; keep ASR ready."""
    global EDITOR_WARM
    editor=MODELS.pop('cleanup',None)
    EDITOR_WARM=False
    if editor is not None:
        del editor
        gc.collect()
        import mlx.core as mx
        mx.clear_cache()

def prewarm(root, *, cleanup='light', cleanup_provider='local'):
    """Warm only installed components. First launch never downloads any weights."""
    global ASR_WARM
    start=time.monotonic()
    editor_requested=local_editor_requested(dict(cleanup=cleanup,cleanup_provider=cleanup_provider))
    if not editor_requested:release_editor()
    asr_available=(Path(root)/'Qwen3-ASR-1.7B-8bit').is_dir()
    editor_available=(Path(root)/'Qwen3-1.7B-4bit').is_dir()
    if asr_available:warm_audio()
    if asr_available and not ASR_WARM:
        import numpy as np
        model=load('asr',root)
        model.generate(np.zeros(16000,dtype=np.float32),hotwords=[],max_tokens=8,temperature=0,verbose=False)
        ASR_WARM=True
    if editor_requested and editor_available:warm_editor(root)
    return {'seconds':time.monotonic()-start,'resident':asr_available and ASR_WARM,'editor_resident':editor_available and EDITOR_WARM,'editor_requested':editor_requested,'audio_resident':asr_available and AUDIO_WARM}

def warm_editor(root):
    """Compile fixed editor instructions off the stop-to-result path, with no user text."""
    global EDITOR_WARM
    if EDITOR_WARM:return
    from cleanup_pipeline import warm_prefixes
    warm_prefixes(load('cleanup',root))
    EDITOR_WARM=True

def release_idle_models():
    # Keep permitted dictation models ready; cloud/disabled policy releases the editor.
    # The optional translation model is reclaimed on idle.
    for role in list(MODELS):
        if role not in ('asr','cleanup'):del MODELS[role]
    gc.collect()
    if MODELS:
        import mlx.core as mx
        mx.clear_cache()

ZH_ORDINALS='一 二 三 四 五 六 七 八 九 十 十一 十二 十三 十四 十五 十六 十七 十八 十九 二十 二十一 二十二 二十三 二十四 二十五 二十六 二十七 二十八 二十九 三十 三十一 三十二'.split()
EN_ORDINALS='first second third fourth fifth sixth seventh eighth ninth tenth'.split()
ORDINAL_VALUES={**dict(zip(ZH_ORDINALS,range(1,33))),**dict(zip(EN_ORDINALS,range(1,11)))}
ORDINAL_MARKER=re.compile(
    r'(?<![^，,；;。.!！？?：:\n])[ \t]*(?:'
    r'第(?P<spoken>[一二三四五六七八九十]{1,3}|[1-9][0-9]?)(?:[个点项条步](?:问题|建议|要求|事项|步骤)?)?'
    r'(?:(?:就是|是)(?!不是|否)|[，,、：:．])'
    r'|(?P<chinese>[一二三四五六七八九十]{1,3})(?:是(?!不是|否)|[、．]|\.[ \t]+)'
    r'|(?P<digit>[1-9][0-9]?)(?:[、．]|[.)][ \t]+)'
    r'|(?P<sequence>首先|其次|最后)[，,：:]'
    r'|(?P<english>'+'|'.join(EN_ORDINALS)+r')(?:ly)?[,：:])[ \t]*',re.I)

IMPLICIT_BOUNDARY=re.compile(r'(?<=[，,。；;！？!?\n])\s*(?:然后|还有|另外|再就是|再把)')
DEPENDENT_ITEM=re.compile(r'^(?:(?:然后|还有|另外)[，,、\s]*)?(?:因为|由于|所以|因此|否则|因而|比如|例如|也就是说|意思是)')
CONDITIONAL_ITEM=re.compile(r'^(?:如果|要是|假如|只要|除非|一旦|等到)')

def render_numbered_items(items):
    lines=[]
    for i,item in enumerate(items,1):
        marker=f'{i}. '
        lines.append(marker+('\n'+' '*len(marker)).join(line.strip() for line in item.splitlines() if line.strip()))
    return '\n'.join(lines)

def format_numbered_list(text,cuts,literals):
    from transcript_rules import DISCUSSION,overlaps
    markers=[m for m in ORDINAL_MARKER.finditer(text) if not overlaps(m.start(),m.end(),literals)]
    if len(markers)<2 or len(markers)>32 or DISCUSSION.search(text[:markers[0].start()]):return None
    labels=[m.group(m.lastgroup) for m in markers]
    numbers=[int(label) if label.isascii() and label.isdigit() else ORDINAL_VALUES.get(label.lower()) for label in labels]
    sequence=labels in (['首先','其次'],['首先','最后'],['首先','其次','最后'])
    if not sequence and numbers!=list(range(1,len(markers)+1)):return None
    # Model cuts after the last entry can retain a separately spoken conclusion.
    end=next((cut for cut in cuts if cut>markers[-1].end() and text[:cut].rstrip().endswith(tuple('。.!！？?'))),len(text))
    items=[text[m.end():stop].strip() for m,stop in zip(markers,[m.start() for m in markers[1:]]+[end])]
    if any(not re.search(r'[^\W_]',item) for item in items):return None
    if any('\n' in text[a:b] and markers[0].start()<=a<end for a,b in literals):return None
    intro=text[:markers[0].start()].strip()
    tail=text[end:].strip()
    return '\n\n'.join(block for block in (intro,render_numbered_items(items),tail) if block)

def format_implicit_list(text,pair,literals):
    from transcript_rules import DISCUSSION,overlaps
    matches=[m for m in IMPLICIT_BOUNDARY.finditer(text) if not overlaps(m.start(),m.end(),literals)]
    if not 1<=len(matches)<=7 or DISCUSSION.search(text[:matches[0].start()]):return None
    cuts=[0]+[m.start() for m in matches]+[len(text)]
    pieces=[text[a:b].strip() for a,b in zip(cuts,cuts[1:])]
    if not all(pieces):return None
    import mlx_lm
    from mlx_lm.sample_utils import make_sampler
    from cleanup_prompts import (
        IMPLICIT_LIST_CHECK,IMPLICIT_LIST_SECOND_CHECK,IMPLICIT_LIST_SELECTION,
        IMPLICIT_LIST_EXAMPLES,IMPLICIT_BOUNDARY_CHECK,IMPLICIT_BOUNDARY_EXAMPLES,
    )
    m,t=pair
    def decide(system,value,max_tokens,examples=()):
        messages=[{'role':'system','content':system}]
        for example,answer in examples:
            messages.extend([{'role':'user','content':example},{'role':'assistant','content':answer}])
        messages.append({'role':'user','content':value})
        prompt=t.apply_chat_template(messages,tokenize=False,add_generation_prompt=True,enable_thinking=False)
        return mlx_lm.generate(m,t,prompt=prompt,max_tokens=max_tokens,sampler=make_sampler(temp=0),verbose=False).strip()
    def yes(answer):return bool(re.fullmatch(r'1[：:]?',answer))
    confident=yes(decide(IMPLICIT_LIST_CHECK,text,5))
    if not confident and not yes(decide(IMPLICIT_LIST_SECOND_CHECK,text,5)):return None
    numbered='\n'.join(f'{i} {piece}' for i,piece in enumerate(pieces,1))
    try:
        ids=json.loads(decide(IMPLICIT_LIST_SELECTION,numbered,24,IMPLICIT_LIST_EXAMPLES))
    except (ValueError,TypeError):
        return None
    if not isinstance(ids,list) or not 2<=len(ids)<=len(pieces) or not all(type(i) is int and 1<=i<=len(pieces) for i in ids):return None
    if ids!=list(range(ids[0],ids[0]+len(ids))):return None
    items=pieces[ids[0]-1:ids[-1]]
    start,end=cuts[ids[0]-1],cuts[ids[-1]]
    if any('\n' in text[a:b] and start<=a<end for a,b in literals):return None
    if any(sum(c.isalnum() for c in item)<3 for item in items):return None
    if any(DEPENDENT_ITEM.match(item) for item in items[1:]):return None
    if any(CONDITIONAL_ITEM.match(item) and item.endswith(('，',',','；',';')) for item in items[:-1]):return None
    if not confident:
        # The broader check admits borderline requests. Require each proposed
        # boundary to separate independently actionable content in that case.
        for left,right in zip(items,items[1:]):
            answer=decide(IMPLICIT_BOUNDARY_CHECK,'A：'+left+'\nB：'+right,4,IMPLICIT_BOUNDARY_EXAMPLES)
            if not yes(answer):return None
    return '\n\n'.join(block for block in (text[:start].strip(),render_numbered_items(items),text[end:].strip()) if block)

def structure(text,pair):
    """Apply verified layout to the exact cleaned text."""
    from cleanup_prompts import STRUCTURE_SYSTEM
    from transcript_rules import protected
    if len(text)>5000:return text,{'reason':'long_input_light_fallback','accepted':False,'used_model':False}
    literals=protected(text)+[m.span() for m in re.finditer(
        r'(?s)```.*?(?:```|$)|~~~.*?(?:~~~|$)|[A-Za-z0-9]+(?:[.,:@][A-Za-z0-9]+)+',text)]
    if IMPLICIT_BOUNDARY.search(text) and format_numbered_list(text,[],literals) is None:
        implicit=format_implicit_list(text,pair,literals)
        if implicit is not None:
            return implicit,{'reason':'source_mapped_implicit_list','accepted':True,'used_model':True,'list':True}
    cuts=[]
    used_model=len(text)>=24
    reason='short_input'
    if used_model:
        import mlx_lm
        from mlx_lm.sample_utils import make_sampler
        m,t=pair
        prompt=t.apply_chat_template([{'role':'system','content':STRUCTURE_SYSTEM},{'role':'user','content':text}],tokenize=False,add_generation_prompt=True,enable_thinking=False)
        answer=mlx_lm.generate(m,t,prompt=prompt,max_tokens=min(12000,max(256,len(text)*3)),sampler=make_sampler(temp=0),verbose=False).strip()
        try:
            parts=json.loads(re.sub(r'^```(?:json)?\s*|\s*```$','',answer))
            if not isinstance(parts,list) or not 1<=len(parts)<=32 or not all(isinstance(p,str) and p.strip() for p in parts):raise ValueError('invalid layout')
            compact=lambda value:re.sub(r'\s+','',value)
            if compact(''.join(parts))!=compact(text):raise ValueError('content changed')
            offsets=[i for i,c in enumerate(text) if not c.isspace()]
            pos=0
            for part in parts[:-1]:
                pos+=len(compact(part));cut=offsets[pos]
                if not text[cut-1].isspace() and text[cut-1] not in '。.!！？?，,；;：:':raise ValueError('unsafe boundary')
                if any(a<cut<b for a,b in literals):raise ValueError('protected literal boundary')
                cuts.append(cut)
            reason='source_mapped_partition'
        except (ValueError,TypeError):
            cuts=[]
            reason='unsafe_layout_rejected'
    numbered=format_numbered_list(text,cuts,literals)
    if numbered is not None:
        return numbered,{'reason':'source_mapped_numbered_list','accepted':True,'used_model':used_model,'list':True}
    exact=[text[a:b].strip() for a,b in zip([0]+cuts,cuts+[len(text)])]
    output='\n\n'.join(exact) if cuts else text
    return output,{'reason':reason,'accepted':reason!='unsafe_layout_rejected','used_model':used_model,'paragraphs':len(exact),'list':False}

def process(job,progress=lambda _:None):
    keep_editor=local_editor_requested(job)
    if not keep_editor:release_editor()
    try:
        return process_dictation(job,progress)
    finally:
        # A failed cloud request can load the local fallback. Release it even
        # when editing/translation fails, after the callee's references unwind.
        if not keep_editor:release_editor()

def process_chunk(job):
    from streaming_pipeline import pretranscribe
    from asr_pipeline import recognize
    if local_editor_requested(job):
        pair=load('cleanup',job['models'])
    else:
        release_editor()
        pair=None
    return pretranscribe(job,load('asr',job['models']),vocabulary(job.get('words',[])),recognize,pair)

def process_dictation(job,progress=lambda _:None):
    words=vocabulary(job.get('words',[]));root=job['models'];mode=job.get('cleanup','light')
    if mode not in ('none','light','structured'):raise ValueError('未知整理档位。')
    meta={'dictionary_count':len(words),'dictionary_sha256':digest(words),'cleanup_mode':mode,'engine_version':1}
    raw=job.get('text','');duration=0;start=time.monotonic();reused=None
    if job.get('audio'):
        import numpy as np, soundfile as sf
        from scipy.signal import resample_poly
        from asr_pipeline import recognize
        progress('正在准备音频')
        a,sr=sf.read(job['audio'],dtype='float32',always_2d=True);duration=len(a)/sr
        if duration>600:raise ValueError('每次录音最多10分钟，原录音已保留。')
        from streaming_pipeline import assemble
        reused,reuse_reason=assemble(job,a,sr,words)
        meta['streaming_reuse']=reuse_reason
        a=a.mean(axis=1)
        if sr!=16000:
            g=math.gcd(sr,16000);a=resample_poly(a,16000//g,sr//g)
        meta['audio_prepare_seconds']=time.monotonic()-start
        progress('正在加载识别模型' if 'asr' not in MODELS else '正在识别')
        before=time.monotonic();model=load('asr',root)
        meta['asr_model_load_seconds']=time.monotonic()-before
        progress('正在识别');before=time.monotonic()
        if reused:raw,asr=reused['raw'],reused['asr']
        else:raw,asr=recognize(model,a,words,language=job.get('language'),max_redecode_seconds=12)
        meta['asr_decode_seconds']=time.monotonic()-before
        meta.update(asr=asr,asr_dictionary_count=len(words),asr_dictionary_sha256=digest(words),asr_seconds=time.monotonic()-start)
        send({'id':job.get('id'),'event':'checkpoint','raw':raw,'duration':duration})
    if not isinstance(raw,str) or len(raw)>32000:raise ValueError('输入过长或格式无效。')
    cleaned=raw;light_meta={'reason':'disabled','used_model':False,'accepted':True}
    cloud = raw.strip() and mode != 'none' and job.get('cleanup_provider') == 'deepseek'
    cloud_succeeded = False
    if cloud:
        from deepseek_cleanup import edit, DeepSeekError
        progress('正在整理')
        before = time.monotonic()
        try:
            cleaned, seconds = edit(raw, mode, words, job.get('deepseek_api_key'))
            cloud_succeeded = True
            meta['deepseek_cleanup'] = {'model': 'deepseek-flash', 'thinking': 'disabled', 'seconds': seconds}
            light_meta = {'reason': 'deepseek', 'used_model': True, 'accepted': True}
        except DeepSeekError as error:
            local_available = (Path(root) / 'Qwen3-1.7B-4bit').is_dir()
            meta['deepseek_cleanup'] = {'reason': str(error), 'fallback': 'local' if local_available else 'raw'}
        meta['cleanup_seconds'] = time.monotonic() - before
    use_local = not cloud_succeeded and meta.get('deepseek_cleanup', {}).get('fallback') != 'raw'
    if raw.strip() and mode!='none' and use_local:
        from cleanup_pipeline import cleanup,should_bypass
        progress('正在轻整理'if mode=='light'else'正在整理')
        before=time.monotonic()
        try:
            if reused and 'cleaned' in reused:
                cleaned,light_meta=reused['cleaned'],reused['cleanup']
            else:cleaned,light_meta=cleanup(None if should_bypass(raw)else load('cleanup',root),raw,words,cache_prefix=True)
            if reused:meta['cleanup_reuse']=reused.get('cleanup_reuse_reason','not_available')
            meta['cleanup_seconds']=meta.get('cleanup_seconds',0)+time.monotonic()-before
            if mode=='structured':
                progress('正在组织段落');before=time.monotonic()
                cleaned,meta['structure']=structure(cleaned,load('cleanup',root))
                meta['structure_seconds']=time.monotonic()-before
        except Exception:
            if not cloud:
                raise
            cleaned=raw
            light_meta={'reason':'local_fallback_failed','used_model':False,'accepted':False}
            meta['deepseek_cleanup']['fallback']='raw'
    meta.update(cleanup=light_meta,cleanup_dictionary_count=len(words)if mode!='none'else 0,cleanup_dictionary_sha256=digest(words)if mode!='none'else None)
    send({'id':job.get('id'),'event':'checkpoint','raw':raw,'cleaned':cleaned,'duration':duration})
    translated=''
    if job.get('translate') and cleaned.strip():
        progress('正在翻译');before=time.monotonic()
        import mlx_lm
        from mlx_lm.sample_utils import make_sampler
        m,t=load('mt',root)
        prompt=t.apply_chat_template([{'role':'user','content':'将以下文本翻译为英语，注意只需要输出翻译后的结果，不要额外解释：\n\n'+cleaned}],tokenize=False,add_generation_prompt=True)
        translated=mlx_lm.generate(m,t,prompt=prompt,max_tokens=min(16384,max(512,len(cleaned)*3)),sampler=make_sampler(temp=0),verbose=False).strip()
        if not translated or '<think>' in translated:raise ValueError('翻译未返回有效结果，源文已保留。')
        meta['translation_seconds']=time.monotonic()-before
    meta['total_seconds']=time.monotonic()-start
    return {'raw':raw,'cleaned':cleaned,'translated':translated,'output':translated if job.get('translate')else cleaned,'duration':duration,'metadata':meta}

def protocol_lines(stream,on_idle,timeout=600):
    """Read whole wire frames without TextIO read-ahead hiding queued requests.

    The app may enqueue prewarm plus recording/chunk jobs in one pipe write.
    Complete frames already in memory must run before waiting for more bytes.
    UTF-8 is decoded by json.loads only after a complete frame is assembled.
    """
    pending=b'';fd=stream.fileno()
    while True:
        if b'\n' in pending:
            line,pending=pending.split(b'\n',1)
            yield line
            continue
        if not select.select([fd],[],[],timeout)[0]:
            on_idle();continue
        block=os.read(fd,65536)
        if not block:
            if pending:yield pending
            return
        pending+=block

def main():
    parent=os.getppid()
    def watch_parent():
        while True:
            time.sleep(2)
            if os.getppid()!=parent:os._exit(0)
    threading.Thread(target=watch_parent,daemon=True).start()
    send({'event':'ready','version':1})
    for line in protocol_lines(sys.stdin,release_idle_models):
        job={}
        try:
            job=json.loads(line)
            # All library diagnostics go to stderr, never contaminate protocol stdout.
            with redirect_stdout(sys.stderr):
                if job.get('action')=='configure_cleanup':
                    if not local_editor_requested(job):release_editor()
                    send({'id':job['id'],'event':'configured'});continue
                if job.get('action')=='prewarm':
                    result=prewarm(job['models'],cleanup=job.get('cleanup','light'),cleanup_provider=job.get('cleanup_provider','local'))
                    send({'id':job['id'],'event':'warmed',**result});continue
                if job.get('action')=='asr_chunk':
                    result=process_chunk(job)
                    send({'id':job['id'],'event':'result',**result});continue
                try:result=process(job,lambda stage:send({'id':job['id'],'event':'progress','stage':stage}))
                finally:
                    from streaming_pipeline import discard
                    discard(job.get('recording_id'))
            send({'id':job['id'],'event':'result',**result})
        except Exception as e:
            send({'id':job.get('id'),'event':'warm_failed' if job.get('action')=='prewarm' else 'error','message':str(e)[:500],'type':type(e).__name__})
if __name__=='__main__':main()
