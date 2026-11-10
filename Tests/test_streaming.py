import unittest,sys,uuid
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import numpy as np
from streaming_pipeline import assemble,CACHE,fingerprint
class CoverageTests(unittest.TestCase):
 def setUp(self):
  CACHE.clear();self.audio=np.arange(200,dtype=np.float32).reshape(100,2)/200
  self.words=['theft','thief','design.md'];self.owner=str(uuid.uuid4());self.tickets=[]
  for index,(a,b,text) in enumerate([(0,40,'这个单词是 theft，'),(40,100,'不是 set。')]):
   ticket=str(uuid.uuid4());self.tickets.append(ticket)
   CACHE[ticket]=dict(owner=self.owner,start=a,count=b-a,sr=24000,channels=2,sha256=fingerprint(self.audio[a:b]),words=tuple(self.words),raw=text,asr={'segments':[{'start_seconds':0,'end_seconds':(b-a)/24000}]},seconds=.2)
 def job(self,tickets=None):return dict(recording_id=self.owner,streaming_tickets=self.tickets if tickets is None else tickets)
 def test_exact_coverage(self):
  result,reason=assemble(self.job(),self.audio,24000,self.words)
  self.assertEqual(result['raw'],'这个单词是 theft，不是 set。');self.assertEqual(result['asr']['verified_pcm_frames'],100)
  self.assertEqual(result['asr']['segments'][1]['start_seconds'],40/24000);self.assertFalse(CACHE)
 def test_changed_dictionary(self):
  self.assertEqual(assemble(self.job(),self.audio,24000,['theft'])[1],'dictionary_changed')
 def test_modified_audio(self):
  a=self.audio.copy();a[3,0]+=.1;self.assertEqual(assemble(self.job(),a,24000,self.words)[1],'pcm_mismatch')
 def test_missing_tail(self):
  self.assertEqual(assemble(self.job(self.tickets[:1]),self.audio,24000,self.words)[1],'incomplete_coverage')
 def test_wrong_order(self):self.assertEqual(assemble(self.job(self.tickets[::-1]),self.audio,24000,self.words)[1],'coverage_mismatch')
 def test_wrong_owner(self):
  job=self.job();job['recording_id']='old';self.assertEqual(assemble(job,self.audio,24000,self.words)[1],'missing_or_stale_segment')
 def test_missing_cache_after_restart(self):
  CACHE.clear();self.assertEqual(assemble(self.job(),self.audio,24000,self.words)[1],'missing_or_stale_segment')
 def test_duplicate_segment(self):self.assertEqual(assemble(self.job([self.tickets[0]]*2),self.audio,24000,self.words)[1],'invalid_tickets')
 def test_sample_rate_changed(self):self.assertEqual(assemble(self.job(),self.audio,16000,self.words)[1],'coverage_mismatch')
 def test_channels_changed(self):self.assertEqual(assemble(self.job(),self.audio[:,:1],24000,self.words)[1],'coverage_mismatch')
 def test_gap(self):
  CACHE[self.tickets[1]]['start']+=1;self.assertEqual(assemble(self.job(),self.audio,24000,self.words)[1],'coverage_mismatch')
 def test_empty_audible_segment(self):
  CACHE[self.tickets[1]]['raw']='';self.assertEqual(assemble(self.job(),self.audio,24000,self.words)[1],'empty_with_signal')
 def test_language_changed(self):
  job=self.job();job['language']='English';self.assertEqual(assemble(job,self.audio,24000,self.words)[1],'language_changed')
 def test_malformed_ticket_falls_back(self):
  self.assertEqual(assemble(self.job([{}]),self.audio,24000,self.words)[1],'invalid_tickets')
 def test_full_worker_retries_original_after_stale_cache(self):
  import tempfile,soundfile as sf,worker
  from unittest.mock import patch
  with tempfile.TemporaryDirectory()as folder:
   path=Path(folder)/'original.wav';audio=np.sin(np.arange(16000)*.02).astype('float32')*.05;sf.write(path,audio,16000,subtype='FLOAT')
   with patch.object(worker,'load',return_value=object()),patch('asr_pipeline.recognize',return_value=('full original fallback',{'segments':[]}))as decode,patch.object(worker,'send')as send:
    result=worker.process(dict(audio=str(path),models='/unused',words=self.words,cleanup='none',recording_id=self.owner,streaming_tickets=['stale']))
   self.assertEqual(result['raw'],'full original fallback');self.assertEqual(result['metadata']['streaming_reuse'],'missing_or_stale_segment');self.assertTrue(np.array_equal(decode.call_args.args[1],audio));self.assertTrue(path.exists());self.assertEqual(send.call_count,2)
 def prepare_edits(self):
  for p in CACHE.values():p.update(mode='light',cleaned=p['raw'],cleanup={'used_model':True},cleanup_seconds=.2)
  job=self.job();job['cleanup']='light';return job
 def test_global_cleanup_reuse(self):
  job=self.prepare_edits();result,_=assemble(job,self.audio,24000,self.words)
  self.assertEqual(result['cleaned'],result['raw']);self.assertEqual(result['cleanup']['reused_chunks'],2)
 def test_cross_chunk_correction_requires_full_edit(self):
  job=self.prepare_edits();CACHE[self.tickets[0]].update(raw='日期是周一，不对，',cleaned='日期是周一。');CACHE[self.tickets[1]].update(raw='改成周五。',cleaned='周五。')
  result,_=assemble(job,self.audio,24000,self.words);self.assertNotIn('cleaned',result);self.assertEqual(result['cleanup_reuse_reason'],'cross_chunk_correction')
 def test_unsafe_chunk_edit_requires_full_edit(self):
  job=self.prepare_edits();CACHE[self.tickets[0]]['cleaned']='这个单词是 set，'
  result,_=assemble(job,self.audio,24000,self.words);self.assertNotIn('cleaned',result)
 def test_mode_change_reuses_audio_but_not_edit(self):
  job=self.prepare_edits();job['cleanup']='structured';result,_=assemble(job,self.audio,24000,self.words)
  self.assertEqual(result['raw'],'这个单词是 theft，不是 set。');self.assertNotIn('cleaned',result)
 def test_ordinary_not_correct_is_not_a_self_correction(self):
  job=self.prepare_edits();CACHE[self.tickets[0]].update(raw='这个是不对的。',cleaned='这个是不对的。');CACHE[self.tickets[1]].update(raw='请检查。',cleaned='请检查。')
  result,_=assemble(job,self.audio,24000,self.words);self.assertIn('cleaned',result)
 def test_thinking_at_pause_is_not_assumed_to_end_message(self):
  job=self.prepare_edits();first='请检查全部录音中的内容是否准确。嗯，然后我想想。';last='预算还没确认，我们周五再决定。'
  CACHE[self.tickets[0]].update(raw=first,cleaned=first);CACHE[self.tickets[1]].update(raw=last,cleaned=last)
  result,_=assemble(job,self.audio,24000,self.words)
  self.assertIn('我想想',result['cleaned']);self.assertIn('预算还没确认',result['cleaned'])
 def test_chunk_thinking_aside_waits_for_full_context(self):
  import tempfile,soundfile as sf
  from unittest.mock import patch
  import streaming_pipeline
  raw='请检查全部录音中的内容是否准确。嗯，然后我想想。'
  with tempfile.TemporaryDirectory()as folder:
   path=Path(folder)/'chunk.wav';sf.write(path,np.ones(16000,dtype='float32')*.1,16000,subtype='FLOAT')
   with patch('cleanup_pipeline.cleanup')as cleaner:
    value=streaming_pipeline.pretranscribe(dict(audio=str(path),recording_id=self.owner,start_frame=0,frame_count=16000,sample_rate=16000,cleanup='light'),object(),self.words,lambda *a,**kw:(raw,{'segments':[]}),object())
   self.assertEqual(CACHE[value['ticket']]['cleaned'],raw);cleaner.assert_not_called()
 def test_withdrawal_spanning_chunks_needs_full_edit(self):
  job=self.prepare_edits()
  CACHE[self.tickets[0]].update(raw='封面保持蓝色。然后，我想问你。',cleaned='封面保持蓝色。然后，我想问你。')
  CACHE[self.tickets[1]].update(raw='没什么。',cleaned='没什么。')
  result,_=assemble(job,self.audio,24000,self.words)
  self.assertNotIn('cleaned',result)
  self.assertEqual(result['cleanup_reuse_reason'],'withdrawn_tail_needs_full_context')
 def test_no_streaming(self):self.assertEqual(assemble({},self.audio,24000,self.words),(None,'not_requested'))
if __name__=='__main__':unittest.main()
