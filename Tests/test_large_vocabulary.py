import sys,unittest
from pathlib import Path
from types import SimpleNamespace
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
from asr_pipeline import recognize
class Decoder:
 def __init__(self,outputs):self.outputs=outputs;self.calls=[]
 def generate(self,a,**kw):
  self.calls.append(kw);return SimpleNamespace(text=self.outputs[len(self.calls)-1],generation_tokens=8)
class LargeVocabulary(unittest.TestCase):
 def samples(self):
  a=np.zeros(32000,dtype=np.float32);a[8000:9600]=.009*np.sin(np.arange(1600)*.12);return a
 def words(self):return ['theft','thief','C','Sonuvi','OpenWhispr','光标','无光标','剪贴板','bross','browser','design.md','design.test','Muse','API']
 def test_full_dictionary_first_and_bounded_review_after_quiet_empty(self):
  words=self.words();model=Decoder(['','Shift.','Theft.']);text,meta=recognize(model,self.samples(),words)
  self.assertEqual(text,'Theft.');self.assertEqual(model.calls[0]['hotwords'],words);self.assertNotIn('hotwords',model.calls[1]);self.assertEqual(model.calls[2]['hotwords'],words[:12]);self.assertTrue(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_newly_recognized_term_survives_compact_dictionary(self):
  words=self.words();model=Decoder(['','Muse.']);text,meta=recognize(model,self.samples(),words)
  self.assertEqual(text,'Muse.');self.assertEqual(len(model.calls),2);self.assertNotIn('compact_dictionary_review',meta['segments'][0])
 def test_nonempty_ordinary_word_is_not_forced_to_dictionary_word(self):
  model=Decoder(['Set.']);text,_=recognize(model,self.samples(),self.words());self.assertEqual(text,'Set.');self.assertEqual(len(model.calls),1)
 def test_empty_compact_review_does_not_erase_existing_result(self):
  model=Decoder(['','Shift.','','']);text,meta=recognize(model,self.samples(),self.words());self.assertEqual(text,'Shift.');self.assertFalse(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_quiet_empty_medium_recording_receives_bounded_review(self):
  audio=np.tile(self.samples(),9);model=Decoder(['','Theft.']);text,meta=recognize(model,audio,self.words());self.assertEqual(text,'Theft.');self.assertEqual(len(model.calls),2);self.assertTrue(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_normal_volume_known_word_contrast_receives_review(self):
  model=Decoder(['这个单词是set，不是set。','这个单词是theft，不是set。']);text,meta=recognize(model,np.ones(32000,dtype=np.float32)*.03,self.words(),max_redecode_seconds=0);self.assertEqual(text,'这个单词是theft，不是set。');self.assertTrue(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_newly_recognized_contrast_term_survives_review(self):
  model=Decoder(['这个单词是Muse，不是API。']);text,meta=recognize(model,np.ones(32000,dtype=np.float32)*.03,self.words(),max_redecode_seconds=0);self.assertIn('Muse',text);self.assertEqual(len(model.calls),1)
 def test_review_cannot_drop_chinese_or_numeric_claims(self):
  model=Decoder(['这个单词是set，不是set，共29个。','这个单词是theft，不是set，共19个。']);text,meta=recognize(model,np.ones(32000,dtype=np.float32)*.03,self.words(),max_redecode_seconds=0);self.assertIn('29',text);self.assertFalse(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_quiet_medium_recording_can_restore_english_tail_without_changing_chinese(self):
  model=Decoder(['如果没付款，就先不要发货。','如果没付款，就先不要发货。Theft, thief.']);text,meta=recognize(model,np.tile(self.samples(),9),self.words());self.assertIn('Theft, thief.',text);self.assertTrue(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_very_quiet_speech_with_a_clear_peak_can_use_original_audio_review(self):
  model=Decoder(['','Thief.']);text,meta=recognize(model,self.samples()*10**(-12/20),self.words());self.assertEqual(text,'Thief.');self.assertEqual(len(model.calls),2);self.assertTrue(meta['segments'][0]['compact_dictionary_review']['accepted'])
 def test_nonspeech_and_normal_level_do_not_get_additional_review(self):
  for audio in [np.ones(32000,dtype=np.float32)*.03,np.ones(32000,dtype=np.float32)*.0001]:
   model=Decoder(['','Set.']);text,meta=recognize(model,audio,self.words());self.assertNotIn('compact_dictionary_review',meta['segments'][0])
if __name__=='__main__':unittest.main()
