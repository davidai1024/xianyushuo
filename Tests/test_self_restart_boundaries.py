import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import unittest
from transcript_rules import prepare_transcript
from cleanup_pipeline import validate

class SelfRestartBoundaries(unittest.TestCase):
 def test_clear_unpunctuated_self_stutters(self):
  for predicate in ['现在也是','觉得要检查','认为需要测试','想先测试','需要确认','希望保留','准备上线','打算重试']:
   for n in [2,3,4]:
    source='我'*n+predicate+'。';want='我'+predicate+'。'
    with self.subTest(source=source):
     self.assertEqual(prepare_transcript(source)[0],want);self.assertTrue(validate(source,want)[0])
 def test_abandoned_bare_thought_is_not_a_second_actor(self):
  pairs=[('先检查权限。我我想，哎，我在想怎么修呢？','先检查权限。我在想怎么修呢？'),('我想，呃，我觉得还要测试。','我觉得还要测试。'),('我想，嗯，我想先测试。','我想先测试。')]
  for source,want in pairs:self.assertEqual(prepare_transcript(source)[0],want)
 def test_ongoing_thought_is_not_a_completed_discovery(self):
  for source in ['我在想怎么修呢？','先检查权限。我我想，哎，我在想怎么修呢？']:
   self.assertEqual(validate(source,'先检查权限。我想到怎么修呢？')[1],'ongoing_thought_changed')
 def test_ongoing_thought_allows_equivalent_progressive_wording(self):
  self.assertTrue(validate('我在想怎么修呢？','我正在想怎么修呢？')[0])
  self.assertNotEqual(validate('我在想怎么修呢？','我正在考虑怎么修呢？')[1],'ongoing_thought_changed')
 def test_emphasis_objects_literals_and_other_actors_survive(self):
  for source in ['我','我我我','我，我，我觉得还需要测试。','你你你怎么这样！','自我我需要建立。','我想你，哎，我在想你。','我想去，哎，我在想怎么修。','我想，哎，他在想怎么修。','请原样保留我我现在也是。','原话是“我我想，哎，我在想怎么修呢？”']:
   with self.subTest(source=source):self.assertEqual(prepare_transcript(source)[0],source)

if __name__=='__main__':unittest.main()
