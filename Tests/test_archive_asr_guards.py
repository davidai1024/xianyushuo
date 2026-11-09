import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import unittest
import numpy as np
from types import SimpleNamespace
from asr_pipeline import recognize
class Capture:
 def __init__(self,outputs):self.outputs=outputs;self.calls=[]
 def generate(self,samples,**kwargs):
  self.calls.append(kwargs);return SimpleNamespace(text=self.outputs[min(len(self.calls)-1,len(self.outputs)-1)],generation_tokens=12)
class ArchiveASRGuards(unittest.TestCase):
 def test_quiet_empty_first_pass_retries_original_audio_without_hints(self):
  samples=np.zeros(32000,dtype=np.float32);samples[8000:9600]=.009*np.sin(np.arange(1600)*.12)
  model=Capture(['','什么？']);words=['theft','thief','C']
  text,meta=recognize(model,samples,words)
  self.assertEqual(text,'什么？');self.assertEqual(len(model.calls),2)
  self.assertEqual(model.calls[0]['hotwords'],words);self.assertNotIn('hotwords',model.calls[1]);self.assertEqual(meta['segments'][0]['unhinted_fallback'],'empty_with_signal')
 def test_quiet_nonempty_first_pass_is_never_overwritten(self):
  samples=np.zeros(32000,dtype=np.float32);samples[8000:9600]=.009*np.sin(np.arange(1600)*.12)
  model=Capture(['C','是。']);text,_=recognize(model,samples,['C','thief'])
  self.assertEqual(text,'C');self.assertEqual(len(model.calls),1)
 def test_low_steady_noise_and_impulse_do_not_trigger_quiet_retry(self):
  impulse=np.zeros(32000,dtype=np.float32);impulse[16000]=.009
  for samples in [np.ones(32000,dtype=np.float32)*.0001,impulse]:
   model=Capture(['','hallucination']);text,_=recognize(model,samples,['C'])
   self.assertEqual(text,'');self.assertEqual(len(model.calls),1)
 def test_digital_silence_never_invokes_decoder(self):
  model=Capture(['hallucination']);text,meta=recognize(model,np.zeros(32000,dtype=np.float32),['C'])
  self.assertEqual(text,'');self.assertEqual(len(model.calls),0);self.assertTrue(meta['digital_silence'])
 def test_spelled_initialism_needs_one_decode_and_full_dictionary(self):
  words=['theft','thief','C','Sonuvi'];model=Capture(['这一列 C I T E 后面都删。'])
  text,meta=recognize(model,np.ones(16000,dtype=np.float32)*.03,words)
  self.assertEqual(len(model.calls),1);self.assertEqual(model.calls[0]['hotwords'],words);self.assertIn('C I T E',text);self.assertEqual(meta['segments'][0]['second_pass_skipped'],'spelled_initialism')
 def test_dictionary_guided_new_hit_is_still_allowed(self):
  model=Capture(['这个 code 放到 default。','这个 theft 放到 default。'])
  text,meta=recognize(model,np.ones(16000,dtype=np.float32)*.03,['theft','thief','C'])
  self.assertEqual(text,'这个 theft 放到 default。');self.assertTrue(meta['segments'][0]['accepted'])
 def test_metalinguistic_letter_contrast_is_not_bypassed(self):
  model=Capture(['这个字母 C 不是 B。'])
  text,meta=recognize(model,np.ones(16000,dtype=np.float32)*.03,['theft','thief','C'])
  self.assertGreaterEqual(len(model.calls),2);self.assertEqual(text,'这个字母 C 不是 B。');self.assertNotEqual(meta['segments'][0].get('second_pass_skipped'),'spelled_initialism')
if __name__=='__main__':unittest.main()
