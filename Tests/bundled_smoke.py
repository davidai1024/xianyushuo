"""Deployed-runtime tests, private recordings, translation and layout invariants."""
from pathlib import Path
import json,subprocess,os,sys,time,hashlib
R=Path(__file__).resolve().parents[1];A=R.parent/'acceptance';sys.path.insert(0,str(A))
from evaluate import evaluate,canonical
bundle=Path('/Applications/点语.app/Contents/Resources');data=Path.home()/'Library/Application Support/Dianyu'
words=[w['word']for w in json.loads((data/'vocabulary.json').read_text())if w['enabled']]
env={**os.environ,'PYTHONPATH':str(bundle/'PythonExtras'),'PYTHONDONTWRITEBYTECODE':'1'}
log=(R/'build/bundled-smoke.stderr.log').open('w')
p=subprocess.Popen([str(bundle/'Runtime/bin/python3'),'-B','-u',str(bundle/'Engine/worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,env=env)
assert json.loads(p.stdout.readline())['event']=='ready'
def call(job):
    job.update(id=str(time.time_ns()),words=words,models=str(data/'models'))
    p.stdin.write(json.dumps(job,ensure_ascii=False)+'\n');p.stdin.flush()
    while True:
        line=p.stdout.readline()
        if not line:raise RuntimeError('Bundled worker exited')
        result=json.loads(line)
        if result['event']in ['result','error','warmed','warm_failed']:return result
rows=[]
try:
    assert call(dict(action='prewarm'))['event']=='warmed'
    for case in json.loads((R/'build/human-private/cases.json').read_text()):
        result=call(dict(audio=case['file'],cleanup='light'))
        rows.append(dict(kind='human',id=case['id'],group=case['group'],**evaluate(case,result.get('output','')),result=result))
    for i,text in enumerate(['第一，检查麦克风和权限。第二，核对个人词表。第三，用同一批录音复测。','明天不要发货。收到付款后再联系客户。金额是29.9元。','保留原话“这个问题是什么？我还没想好”。路径是 /Users/test/cache.json，不要改成其他路径。']):
        result=call(dict(text=text,cleanup='structured'));output=result.get('output','')
        rows.append(dict(kind='structured-special',id=str(i),input=text,result=result,**{'pass':canonical(output)==canonical(text) and (i==2 or '\n'in output),'failures':[]}))
    # The same long paused personal recording has one known failure; do not erase it.
finally:
    p.stdin.close();p.wait(timeout=30);log.close()
(R/'build/bundled-smoke.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict','/Applications/点语.app'],check=True)
print(json.dumps({kind:{'total':sum(r['kind']==kind for r in rows),'pass':sum(r['kind']==kind and r['pass']for r in rows)}for kind in set(r['kind']for r in rows)},ensure_ascii=False))
