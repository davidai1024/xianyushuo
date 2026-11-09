import sys,unittest
from pathlib import Path
from types import SimpleNamespace
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
from asr_pipeline import recognize

class GainGuards(unittest.TestCase):
 def run_audio(self,answers):
  class Decoder:
   def __init__(self):self.calls=[]
   def generate(self,a,**kw):
    self.calls.append((float(np.max(np.abs(a))),kw))
    return SimpleNamespace(text=answers[len(self.calls)-1])
  audio=np.zeros(56000,dtype=np.float32);audio[100:300]=.03
  model=Decoder();text,meta=recognize(model,audio,['C','theft'])
  return text,meta,model.calls
 def test_quiet_letter_keeps_raw_decode(self):
  text,meta,calls=self.run_audio(['C。'])
  self.assertEqual(text,'C。');self.assertEqual(len(calls),1)
  self.assertFalse(meta['segments'][0]['normalized_first_pass'])
 def test_quiet_chinese_is_not_replaced_by_gain(self):
  text,_,calls=self.run_audio(['可不可以自己有一个有一个？'])
  self.assertEqual(text,'可不可以自己有一个有一个？');self.assertEqual(len(calls),1)
 def test_uncertain_english_needs_unhinted_agreement(self):
  text,meta,calls=self.run_audio(['A theft.','Theft.','Theft.'])
  self.assertEqual(text,'Theft.');self.assertTrue(meta['segments'][0]['quiet_retry_accepted'])
  self.assertGreater(calls[1][0],calls[0][0]);self.assertNotIn('hotwords',calls[2][1])
 def test_unhinted_disagreement_preserves_raw(self):
  text,_,calls=self.run_audio(['A theft.','Theft.','A theft.'])
  self.assertEqual(text,'A theft.');self.assertEqual(len(calls),3)

if __name__=='__main__':unittest.main()
