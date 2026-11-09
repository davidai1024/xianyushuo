"""Regression for read-ahead losing the next request during prewarming."""
import unittest,sys,os,json,subprocess,select,time,tempfile,threading,io
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import worker
class ProtocolTests(unittest.TestCase):
    def test_batched_prewarm_then_jobs_without_extra_wakeup(self):
        script=os.environ.get('DIANYU_TEST_WORKER',str(Path(worker.__file__)))
        with tempfile.TemporaryDirectory()as root:
            p=subprocess.Popen([sys.executable,'-B','-u',script],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
            jobs=[dict(id='warm',action='prewarm',models=root),dict(id='one',models=root,text='中英 C theft thief',cleanup='none'),dict(id='two',models=root,text='第二条不能等下一次按键',cleanup='none')]
            p.stdin.write(b''.join(json.dumps(x,ensure_ascii=False).encode()+b'\n'for x in jobs));p.stdin.flush()
            pending=b'';events=[];deadline=time.monotonic()+4
            try:
                while time.monotonic()<deadline and len([x for x in events if x['event']in('warmed','result')])<3:
                    ready=select.select([p.stdout.fileno()],[],[],max(0,deadline-time.monotonic()))[0]
                    if not ready:break
                    block=os.read(p.stdout.fileno(),65536)
                    if not block:break
                    pending+=block
                    while b'\n'in pending:
                        line,pending=pending.split(b'\n',1);events.append(json.loads(line))
                results={x.get('id'):x for x in events if x['event']in('warmed','result')}
                self.assertEqual(set(results),{'warm','one','two'},'Batched requests must all complete while stdin stays open')
                self.assertEqual(results['one']['output'],jobs[1]['text']);self.assertEqual(results['two']['output'],jobs[2]['text'])
            finally:
                p.stdin.close();p.terminate();p.wait(timeout=5);p.stdout.close()
    def test_utf8_fragmentation_multiple_lines_and_final_eof(self):
        read,write=os.pipe();parts=[('中'*30000+' C theft thief').encode(),b'{}',b'last-without-newline'];payload=b'\n'.join(parts)
        def feed():
            try:
                for offset in range(0,len(payload),137):os.write(write,payload[offset:offset+137])
            finally:os.close(write)
        thread=threading.Thread(target=feed);thread.start()
        with os.fdopen(read,'rb',buffering=0)as stream:actual=list(worker.protocol_lines(stream,lambda:None,timeout=0.1))
        thread.join();self.assertEqual(actual,parts)
    def test_idle_callback_then_shutdown(self):
        read,write=os.pipe();idle=[]
        def feed():time.sleep(.06);os.close(write)
        thread=threading.Thread(target=feed);thread.start()
        with os.fdopen(read,'rb',buffering=0)as stream:rows=list(worker.protocol_lines(stream,lambda:idle.append(True),timeout=.01))
        thread.join();self.assertEqual(rows,[]);self.assertTrue(idle)
if __name__=='__main__':unittest.main()
