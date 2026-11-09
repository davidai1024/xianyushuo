"""Full local regression through the exact stdio protocol used by the native app."""
from pathlib import Path
import sys,os,json,time,subprocess,hashlib,collections
R=Path(__file__).resolve().parents[1];A=R.parents[0]/'acceptance'
sys.path.insert(0,str(A))
from evaluate import evaluate
from run_audio import audio_case,spoken_numbers
OUT=Path(os.environ.get('DIANYU_TEST_OUTPUT',str(R/'build/acceptance')));OUT.mkdir(exist_ok=True)
DATA=Path.home()/'Library/Application Support/Dianyu'
words=[v['word']for v in json.loads((DATA/'vocabulary.json').read_text())if v['enabled']]
if os.environ.get('DIANYU_TEST_WORDS'):words=json.loads(os.environ['DIANYU_TEST_WORDS'])
python=R/'build/Runtime/bin/python3'
env={**os.environ,'PYTHONPATH':str(R/'build/PythonExtras'),'PYTHONDONTWRITEBYTECODE':'1'}
err=(OUT/'engine.stderr.log').open('w')
p=subprocess.Popen([str(python),'-B','-u',str(R/'Engine/worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,text=True,env=env)
assert json.loads(p.stdout.readline())['event']=='ready'
def call(job):
    while True:
        try:
            recent=json.loads((DATA/'sessions.json').read_text())[:2]
            active=any(r['status']in ['recording','processing']and r['created']>time.time()-978307200-600 for r in recent)
        except Exception:active=False
        if not active:break
        time.sleep(.5)
    ident=str(time.time_ns());job.update(id=ident,models=str(DATA/'models'),words=words)
    p.stdin.write(json.dumps(job,ensure_ascii=False)+'\n');p.stdin.flush()
    checkpoints=[]
    while True:
        line=p.stdout.readline()
        if not line:raise RuntimeError('Worker exited')
        value=json.loads(line)
        if value.get('event')=='checkpoint':checkpoints.append(value)
        if value.get('event')in ['result','error','warmed','warm_failed']:
            value['checkpoint_count']=len(checkpoints);return value
rows=[]
(OUT/'results.jsonl').write_text('')
assert call(dict(action='prewarm'))['event']=='warmed'
def record(kind,case,result,verdict):
    row=dict(kind=kind,id=case['id'],category=case.get('category','专项'),input=case.get('text',''),**verdict,result=result)
    rows.append(row)
    with (OUT/'results.jsonl').open('a')as f:f.write(json.dumps(row,ensure_ascii=False)+'\n')
    counts=collections.Counter((r['kind'],'pass'if r['pass']else'fail')for r in rows)
    (OUT/'progress.json').write_text(json.dumps({str(k):v for k,v in counts.items()},ensure_ascii=False,indent=2))
    if len(rows)%25==0:print('completed',len(rows),flush=True)

cases=[c for name in ['corpus.json','challenge-corpus.json','fresh-corpus.json']for c in json.loads((A/name).read_text()) if not c.get('audio_only')]
assert len(cases)==875
if os.environ.get('DIANYU_TEST_AUDIO_ONLY')=='1':cases=[]
manifest=json.loads((A/'audio-manifest.json').read_text())
freeze={'engine_files':{x.name:hashlib.sha256(x.read_bytes()).hexdigest()for x in (R/'Engine').glob('*.py')},'text_count':len(cases),'audio_count':len(manifest),'dictionary_sha256':hashlib.sha256(json.dumps(words,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()}
(OUT/'freeze.json').write_text(json.dumps(freeze,ensure_ascii=False,indent=2))
try:
    for c in cases:
        result=call(dict(text=c['text'],cleanup='light'));verdict=evaluate(c,result.get('output',''))
        if result['event']=='error':verdict={'pass':False,'failures':[{'kind':'engine_error'}]}
        record('light-text',c,result,verdict)
    # None is deliberately scored against exact raw input, including whitespace.
    for c in cases[::17]:
        result=call(dict(text=c['text'],cleanup='none'))
        record('none-text',c,result,dict(pass_=False)if False else {'pass':result.get('output')==c['text'],'failures':[]if result.get('output')==c['text']else[{'kind':'not_verbatim'}]})
    structured=[c for c in cases if len(c['text'])>35][::7][:48]
    for c in structured:
        result=call(dict(text=c['text'],cleanup='structured'));record('structured-text',c,result,evaluate(c,result.get('output','')))
    for c in manifest:
        assert hashlib.sha256(Path(c['file']).read_bytes()).hexdigest()==c['sha256']
        result=call(dict(audio=c['file'],cleanup='light'));verdict=evaluate(audio_case(c),spoken_numbers(result.get('output','')))
        if c.get('ambiguous'):verdict['diagnostic_only']=True
        record('audio',c,result,verdict)
    # Direct translation: check concrete facts/negations, not exact stylistic wording.
    translations=[('如果明天还没有收到付款，就先不要发货。',['payment'],['not','until']),('会议约周一，不对，改成周三，不对，最终改成周五。',['friday'],[]),('这个单词是 thief，不是 theft。',['thief','theft'],['not']),('价格是负19.9元，不对，改成29.9元。',['29.9'],[])]
    for i,(text,terms,one_of) in enumerate(translations):
        result=call(dict(text=text,cleanup='light',translate=True));value=result.get('output','').lower();fail=[term for term in terms if term not in value]
        if one_of and not any(term in value for term in one_of):fail.append('negative_condition')
        record('translation',dict(id='translation'+str(i),text=text),result,{'pass':not fail,'failures':fail})
finally:
    p.stdin.close();p.wait(timeout=30);err.close()
summary={}
for kind in dict.fromkeys(r['kind']for r in rows):
    selected=[r for r in rows if r['kind']==kind and not r.get('diagnostic_only')];summary[kind]=dict(total=len(selected),passed=sum(r['pass']for r in selected),failed=sum(not r['pass']for r in selected))
(OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2));print(json.dumps(summary,ensure_ascii=False),flush=True)
