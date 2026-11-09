"""Verified background ASR reuse. Never trust a partial text without exact PCM coverage."""
from collections import OrderedDict
import hashlib,math,time,uuid,re
import numpy as np
from scipy.signal import resample_poly
CACHE=OrderedDict()

def discard(owner):
    if not owner:return
    for ticket in list(CACHE):
        if CACHE[ticket]['owner']==owner:CACHE.pop(ticket,None)

def fingerprint(audio):return hashlib.sha256(np.ascontiguousarray(audio,dtype=np.float32).tobytes()).hexdigest()

def pretranscribe(job,model,words,recognize,cleanup_pair=None):
    import soundfile as sf
    native,sr=sf.read(job['audio'],dtype='float32',always_2d=True)
    count=len(native);start=job.get('start_frame');owner=job.get('recording_id')
    if not isinstance(owner,str) or not owner or not isinstance(start,int) or start<0 or count!=job.get('frame_count') or sr!=job.get('sample_rate'):
        raise ValueError('分段音频信息不一致。')
    if not 0<count<=sr*600:raise ValueError('分段长度无效。')
    mono=native.mean(axis=1)
    if sr!=16000:
        g=math.gcd(sr,16000);mono=resample_poly(mono,16000//g,sr//g)
    before=time.monotonic();raw,meta=recognize(model,mono,words,language=job.get('language'),max_redecode_seconds=0)
    asr_seconds=time.monotonic()-before;cleaned=None;clean_meta={};clean_seconds=0
    mode=job.get('cleanup','none')
    if mode!='none' and raw.strip() and cleanup_pair is not None:
        from cleanup_pipeline import cleanup
        from transcript_rules import remove_thinking_tail
        before=time.monotonic()
        if remove_thinking_tail(raw)[1]:
            # A pause is not the end of the message. Keep this cue until the
            # full transcript can distinguish thinking + new facts from finish.
            cleaned=raw
            clean_meta={'accepted':True,'used_model':False,'reason':'thinking_aside_pending_full_context'}
        else:cleaned,clean_meta=cleanup(cleanup_pair,raw,words,cache_prefix=True)
        clean_seconds=time.monotonic()-before
    ticket=str(uuid.uuid4())
    CACHE[ticket]=dict(owner=owner,start=start,count=count,sr=sr,channels=native.shape[1],sha256=fingerprint(native),words=tuple(words),language=job.get('language'),raw=raw,asr=meta,seconds=asr_seconds,mode=mode,cleaned=cleaned,cleanup=clean_meta,cleanup_seconds=clean_seconds)
    while len(CACHE)>128:CACHE.popitem(last=False)
    return dict(ticket=ticket,frames=count,seconds=asr_seconds+clean_seconds)

def assemble(job,native,sr,words):
    tickets=job.get('streaming_tickets')
    if not tickets:return None,'not_requested'
    owner=job.get('recording_id');parts=[];cursor=0
    try:
        if not isinstance(tickets,list) or not all(isinstance(t,str)for t in tickets) or len(tickets)>80 or len(set(tickets))!=len(tickets):return None,'invalid_tickets'
        for ticket in tickets:
            part=CACHE.get(ticket)
            if not part or part['owner']!=owner:return None,'missing_or_stale_segment'
            if part['words']!=tuple(words):return None,'dictionary_changed'
            if part.get('language')!=job.get('language'):return None,'language_changed'
            if part['sr']!=sr or part['channels']!=native.shape[1] or part['start']!=cursor:return None,'coverage_mismatch'
            end=cursor+part['count']
            if end>len(native) or fingerprint(native[cursor:end])!=part['sha256']:return None,'pcm_mismatch'
            # Empty recognition of an audible segment must retry the full original.
            if not part['raw'].strip() and np.max(np.abs(native[cursor:end]))>0.0001:return None,'empty_with_signal'
            parts.append(part);cursor=end
        if cursor!=len(native):return None,'incomplete_coverage'
        result=''
        for part in parts:
            value=part['raw'].strip()
            if not value:continue
            space=' ' if result and result[-1:].isascii() and value[:1].isascii() else ''
            result+=space+value
        segments=[]
        for part in parts:
            offset=part['start']/sr
            for segment in part['asr'].get('segments',[]):
                segments.append({**segment,'start_seconds':segment.get('start_seconds',0)+offset,'end_seconds':segment.get('end_seconds',0)+offset})
        output=dict(raw=result,asr={'streaming':True,'verified_pcm_frames':cursor,'chunk_count':len(parts),'background_compute_seconds':sum(p['seconds']for p in parts),'segments':segments})
        mode=job.get('cleanup','none')
        if mode!='none' and all(p.get('mode')==mode and (p.get('cleaned') is not None or not p['raw'].strip())for p in parts):
            from cleanup_pipeline import validate,repair_connective_starts,light_format
            from transcript_rules import prepare_transcript
            # A later correction may revoke an earlier chunk. Always edit the full source.
            cross_correction=re.search(r'(?<!对)不对(?!的|吗|[？?])|说错|改成|改为|更正|作废|算了|sorry|actually|I mean',result,re.I)
            candidate=''.join(((' ' if i and p.get('cleaned','') and p['cleaned'][:1].isascii() else '')+(p.get('cleaned') or ''))for i,p in enumerate(parts))
            candidate,preparation=prepare_transcript(candidate);candidate=light_format(repair_connective_starts(candidate))
            prepared,_=prepare_transcript(result);prepared=repair_connective_starts(prepared)
            accepted,reason=validate(prepared,candidate,words)
            output['cleanup_reuse_reason']='cross_chunk_correction' if cross_correction else reason
            if accepted and not cross_correction:
                output['cleaned']=candidate
                output['cleanup']=dict(accepted=True,used_model=any(p.get('cleanup',{}).get('used_model')for p in parts),reason='globally_validated_background_cleanup',reused_chunks=len(parts),background_seconds=sum(p.get('cleanup_seconds',0)for p in parts),preparation=preparation)
        return output,'verified_exact_pcm_coverage'
    finally:
        for ticket in tickets if isinstance(tickets,list) else []:
            if isinstance(ticket,str):CACHE.pop(ticket,None)
