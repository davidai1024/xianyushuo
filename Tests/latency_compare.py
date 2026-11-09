from pathlib import Path
import subprocess,os,json,time,argparse
R=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--label',required=True);p.add_argument('--engine',type=Path,required=True);p.add_argument('--prewarm',action='store_true');args=p.parse_args()
data=Path.home()/'Library/Application Support/Dianyu';rows=json.loads((data/'sessions.json').read_text());record=next(r for r in rows if r['raw'].casefold()=='thief, not theft.')
env={**os.environ,'PYTHONPATH':str(R/'build/PythonExtras'),'PYTHONDONTWRITEBYTECODE':'1'}
log=(R/'build'/('latency-'+args.label+'.stderr.log')).open('w')
worker=subprocess.Popen([str(R/'build/Runtime/bin/python3'),'-B','-u',str(args.engine/'worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,env=env)
assert json.loads(worker.stdout.readline())['event']=='ready'
def call(job):
    job.update(id=str(time.time_ns()),models=str(data/'models'));worker.stdin.write(json.dumps(job,ensure_ascii=False)+'\n');worker.stdin.flush()
    while True:
        line=worker.stdout.readline()
        if not line:raise RuntimeError('Worker exited')
        value=json.loads(line)
        if value['event']in ['result','error','warmed','warm_failed']:return value
results=[]
try:
    if args.prewarm:results.append({'kind':'prewarm','result':call(dict(action='prewarm'))})
    for i in range(5):
        start=time.monotonic();result=call(dict(audio=str(data/'Recordings'/record['audioFile']),words=record['words'],cleanup='none'))
        results.append({'kind':'audio','repeat':i,'wall_seconds':time.monotonic()-start,'result':result})
finally:worker.stdin.close();worker.wait(timeout=30);log.close()
(R/'build'/('latency-'+args.label+'.json')).write_text(json.dumps(results,ensure_ascii=False,indent=2))
print(json.dumps([{'kind':r['kind'],'seconds':r.get('wall_seconds'),'output':r['result'].get('output'),'event':r['result']['event']}for r in results],ensure_ascii=False),flush=True)
