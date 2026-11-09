"""Replay frozen manifests through two real workers; no microphone or paste side effects."""
import argparse, collections, hashlib, json, os, subprocess, sys, time
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--baseline',type=Path,required=True)
p.add_argument('--candidate',type=Path,required=True)
p.add_argument('--manifest',type=Path,action='append',required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--candidate-words',type=Path,required=True)
p.add_argument('--reuse-baseline',type=Path)
args=p.parse_args()
R=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(R.parent/'acceptance'))
from evaluate import evaluate
D=Path.home()/'Library/Application Support/Dianyu'
words=[x['word']for x in json.loads((D/'vocabulary.json').read_text())if x['enabled']]
if args.reuse_baseline:words=json.loads((args.reuse_baseline.parent/'freeze.json').read_text())['baseline_words']
candidate_words=json.loads(args.candidate_words.read_text())
cases=[c for f in args.manifest for c in json.loads(f.read_text())]
args.output.mkdir(parents=True,exist_ok=True)
freeze={'manifests':{str(f):hashlib.sha256(f.read_bytes()).hexdigest()for f in args.manifest},'baseline_words':words,'candidate_words':candidate_words,'engines':{label:{f.name:hashlib.sha256(f.read_bytes()).hexdigest()for f in folder.glob('*.py')}for label,folder in [('before',args.baseline),('candidate',args.candidate)]}}
(args.output/'freeze.json').write_text(json.dumps(freeze,ensure_ascii=False,indent=2))
out=args.output/'results.jsonl'
out.write_text('')
if args.reuse_baseline:
 prior_freeze=json.loads((args.reuse_baseline.parent/'freeze.json').read_text())
 assert prior_freeze['baseline_words']==words
 assert prior_freeze['engines']['before']==freeze['engines']['before']
 assert prior_freeze['manifests']==freeze['manifests']
 old=[json.loads(x)for x in args.reuse_baseline.read_text().splitlines()]
 baseline=[r for r in old if r['variant']=='before']
 assert {r['id']for r in baseline}=={c['id']for c in cases}
 out.write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n'for r in baseline))
 freeze['reused_baseline_sha256']=hashlib.sha256(args.reuse_baseline.read_bytes()).hexdigest()
 (args.output/'freeze.json').write_text(json.dumps(freeze,ensure_ascii=False,indent=2))
for variant,folder,terms in [('before',args.baseline,words),('candidate',args.candidate,candidate_words)]:
 if variant=='before'and args.reuse_baseline:continue
 err=(args.output/(variant+'.stderr.log')).open('w')
 process=subprocess.Popen([str(R/'build/Runtime/bin/python3'),'-B','-u',str(folder/'worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,text=True,env={**os.environ,'PYTHONPATH':str(R/'build/PythonExtras'),'PYTHONDONTWRITEBYTECODE':'1'})
 assert json.loads(process.stdout.readline())['event']=='ready'
 try:
  for i,c in enumerate(cases):
   while True:
    recent=json.loads((D/'sessions.json').read_text())[:2]
    if not any(x['status']in ['recording','processing']and x['created']>time.time()-978307200-600 for x in recent):break
    time.sleep(.5)
   assert hashlib.sha256(Path(c['file']).read_bytes()).hexdigest()==c['sha256']
   job=dict(id=str(i),models=str(D/'models'),words=terms,audio=c['file'],cleanup='light')
   process.stdin.write(json.dumps(job,ensure_ascii=False)+'\n');process.stdin.flush()
   while True:
    line=process.stdout.readline()
    if not line:raise RuntimeError('Worker exited')
    result=json.loads(line)
    if result['event']in ['result','error']:break
   verdict=evaluate(c,result.get('output',''))
   row=dict(id=c['id'],group=c.get('group',c['id']),variant=variant,category=c['category'],reference=c.get('reference'),gain_db=c.get('gain_db',0),diagnostic_only=c.get('diagnostic_only',False),**verdict,result=result)
   with out.open('a')as f:f.write(json.dumps(row,ensure_ascii=False)+'\n')
   if i%10==0:print(variant,i+1,'/',len(cases),flush=True)
 finally:
  process.stdin.close();process.wait(timeout=30);err.close()
rows=[json.loads(x)for x in out.read_text().splitlines()]
summary={}
for variant in ['before','candidate']:
 selected=[r for r in rows if r['variant']==variant and not r['diagnostic_only']]
 summary[variant]={category:dict(total=len(group),passed=sum(x['pass']for x in group))for category in dict.fromkeys(x['category']for x in selected)for group in [[x for x in selected if x['category']==category]]}
(args.output/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
print(json.dumps(summary,ensure_ascii=False),flush=True)
