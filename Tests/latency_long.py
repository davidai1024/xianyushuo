"""Same immutable long recordings, before/after; only timings and text digests exported."""
from pathlib import Path
import os,subprocess,time,json,hashlib
R=Path(__file__).resolve().parents[1];D=Path.home()/'Library/Application Support/Dianyu'
manifest=json.loads((R.parent/'speed-cleanup/recent-private-manifest.json').read_text())
words=[x['word']for x in json.loads((D/'vocabulary.json').read_text())if x['enabled']]
rows=[]
for label,engine,warm in [('before',R/'build/latency-before-engine',False),('after',Path('/Applications/点语.app/Contents/Resources/Engine'),True)]:
    bundle=Path('/Applications/点语.app/Contents/Resources')
    env={**os.environ,'PYTHONPATH':str(bundle/'PythonExtras'),'PYTHONDONTWRITEBYTECODE':'1'}
    with (R/'build'/('latency-long-'+label+'.stderr.log')).open('w')as log:
        p=subprocess.Popen([str(bundle/'Runtime/bin/python3'),'-B','-u',str(engine/'worker.py')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True,env=env)
        assert json.loads(p.stdout.readline())['event']=='ready'
        def call(job):
            job.update(id=str(time.time_ns()),models=str(D/'models'),words=words)
            p.stdin.write(json.dumps(job)+'\n');p.stdin.flush()
            while True:
                line=p.stdout.readline()
                if not line:raise RuntimeError('Worker stopped')
                value=json.loads(line)
                if value['event']in ['result','error','warmed','warm_failed']:return value
        try:
            if warm:assert call(dict(action='prewarm'))['event']=='warmed'
            for case in manifest:
                path=Path(case['file']);assert hashlib.sha256(path.read_bytes()).hexdigest()==case['sha256']
                wav=path.with_suffix('.wav');wav_hash=hashlib.sha256(wav.read_bytes()).hexdigest()
                for repeat in range(2):
                    start=time.monotonic();result=call(dict(audio=str(wav),cleanup='none'));wall=time.monotonic()-start
                    assert result['event']=='result',result
                    rows.append(dict(label=label,id=case['id'],repeat=repeat,duration=result['duration'],wall_seconds=wall,asr_seconds=result['metadata']['asr_seconds'],decode_seconds=result['metadata'].get('asr_decode_seconds'),wav_sha256=wav_hash,output_sha256=hashlib.sha256(result['output'].encode()).hexdigest()))
                    print(json.dumps(rows[-1]),flush=True)
        finally:p.stdin.close();p.wait(timeout=30)
for case in manifest:
    selected=[r for r in rows if r['id']==case['id']]
    assert len({r['output_sha256']for r in selected})==1,'Changed output'
(R/'build/latency-long.json').write_text(json.dumps(rows,indent=2))
print('Same waveform, dictionary and output verified.',flush=True)
