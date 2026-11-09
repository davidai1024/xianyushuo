import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
from transcript_rules import prepare_transcript
from cleanup_pipeline import cleanup
class FillerBoundaryTests(unittest.TestCase):
 def test_remove_only_filled_pauses(self):
  for source,expected in [('输入框，嗯，写入验证，请保留这句话。','输入框，写入验证，请保留这句话。'),('嗯，我想确认一下，这个单词是 thief，不是 theft。','我想确认一下，这个单词是 thief，不是 theft。'),('先打开设置，嗯，然后检查权限。','先打开设置，然后检查权限。')]:
   self.assertEqual(prepare_transcript(source)[0],expected)
 def test_meaningful_responses_and_literals(self):
  for source in ['嗯','嗯嗯','嗯，好的。','嗯，我同意。','嗯，行','嗯哼，我知道了。','他回答，嗯，我想一想。','他说“嗯”，我也说“嗯”。','请原样保留“嗯”。','不要删除语气词嗯。','The word um must stay.']:
   self.assertEqual(prepare_transcript(source)[0],source)
 def test_none_and_light_contract(self):
  import worker
  source='输入框，嗯，写入验证，请保留这句话。'
  self.assertEqual(worker.process(dict(models='/missing',words=[],text=source,cleanup='none'))['output'],source)
 def test_rejected_model_cannot_restore_removed_pause(self):
  import mlx_lm
  from unittest.mock import patch
  class Tokenizer:
   def apply_chat_template(self,*args,**kwargs):return 'unused'
  with patch.object(mlx_lm,'generate',return_value='输入框写入验证，保留这句话。'):
   output,meta=cleanup((object(),Tokenizer()),'输入框，嗯，写入验证，请保留这句话。')
  self.assertNotIn('嗯',output);self.assertIn('请',output);self.assertFalse(meta['accepted'])
if __name__=='__main__':unittest.main()
