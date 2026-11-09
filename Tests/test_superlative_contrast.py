import sys, unittest
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import cleanup_pipeline as c
from transcript_rules import prepare_transcript

class SuperlativeContrastTests(unittest.TestCase):
 def test_stutter_with_unrelated_contrast(self):
  source='报表能打开，但是有些数据看不清。你确定这个方案是最最最快、效果最好的吗？'
  candidate='报表能打开，但有些数据看不清。你确定这个方案是最快、效果最好的吗？'
  self.assertNotIn('最最',prepare_transcript(source)[0])
  self.assertEqual(c.validate(source,candidate),(True,'accepted'))
 def test_superlative_predicates(self):
  for adjective in ['快','好','准确','稳定','清晰','简单','安全','成熟','合适']:
   for count in [2,3,4,6]:
    source='这个方案是'+'最'*count+adjective+'的吗？'
    want='这个方案是最'+adjective+'的吗？'
    with self.subTest(source=source):
     self.assertEqual(prepare_transcript(source)[0],want)
     self.assertTrue(c.validate(source,want)[0])
 def test_literals_and_other_emphasis(self):
  for source in ['最最最','最，最，最快。','他说“最最最快”。','请原样输入最最最快。','请逐字保留最最好的。','`最最最快`','https://example.com/最最最快','这个词是最最最快。','这里多了几个最，最最最快不对。','我要强调最最好的。','非常非常快，真的真的好。','这个最小值和最大值都要保留。']:
   with self.subTest(source=source):self.assertEqual(prepare_transcript(source)[0],source)
 def test_concise_contrast_and_guard(self):
  for before,after in [('但是','但'),('但','但是')]:
   self.assertTrue(c.validate('速度快，'+before+'效果不好。','速度快，'+after+'效果不好。')[0])
  for before,after in [('但是','不过'),('不过','但')]:
   self.assertNotEqual(c.validate('速度快，'+before+'效果不好。','速度快，'+after+'效果不好。')[1],'contrast_lost')
  for candidate in ['速度快，效果不好。','速度快，不但效果不好。','速度快，但愿效果不好。','速度快，但凡效果不好。']:
   with self.subTest(candidate=candidate):self.assertEqual(c.validate('速度快，但是效果不好。',candidate)[1],'contrast_lost')
 def test_none_is_verbatim(self):
  import worker
  source='嗯，你确定这是最最最快的吗？'
  with patch.object(worker,'send'):
   self.assertEqual(worker.process(dict(models='/missing',text=source,words=[],cleanup='none'))['output'],source)

if __name__=='__main__':unittest.main()
