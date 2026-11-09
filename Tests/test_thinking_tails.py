import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
from transcript_rules import prepare_transcript
class ThinkingTailTests(unittest.TestCase):
 def test_complete_thinking_asides_removed(self):
  body='请复测分段以后有没有漏字，英文 C theft thief 有没有退步？'
  for tail in ['嗯，然后我想想。嗯，没，没了。','嗯，然后我想想。没没的。','嗯，我想想，没有了。','然后我想想，没了。','嗯，我想想。','嗯。然后我想想，暂时没有了。']:
   with self.subTest(tail=tail):
    result,meta=prepare_transcript(body+tail);self.assertEqual(result,body);self.assertEqual(meta['thinking_tail_removals'],1)
 def test_meaningful_closures_and_plans_preserved(self):
  for text in ['嗯，没了。','嗯，我想想。','我想想再决定。','请让我想想。','库存已经没了，请明天补货。','请检查会议纪要有没有遗漏。我想想，周五再确认。','请检查会议纪要有没有遗漏。嗯，我想想，预算还没有确认。','请检查会议纪要有没有遗漏。然后我想想再告诉你。','他说“嗯，然后我想想，没了”。','请原样保留嗯然后我想想没没了这几个字。','请记录这段完整原话。他回答。嗯，我想想，没了。','这件事情还需要大家一起确认。我想想，没收押金是否合理？']:
   with self.subTest(text=text):
    result,meta=prepare_transcript(text);self.assertEqual(meta['thinking_tail_removals'],0)
    if '原样'in text or '“'in text:self.assertEqual(result,text)
 def test_sentence_boundary_filled_pause(self):
  for sep in ['。','？','！',';','\n']:
   with self.subTest(sep=sep):self.assertEqual(prepare_transcript('请先检查权限'+sep+'嗯，然后打开设置。')[0],'请先检查权限'+sep+'然后打开设置。')
 def test_acknowledgement_and_report_preserved(self):
  for text in ['检查通过。嗯，我同意。','检查通过？嗯，好的。','他回答。嗯，我想一想。','请原样保留“嗯”。','The code en must remain.']:
   self.assertEqual(prepare_transcript(text)[0],text)
 def test_function_word_partial_restarts(self):
  for source,expected in [('就就这这里不能只用一种动效。','就这里不能只用一种动效。'),('那那个按钮先不要删。','那个按钮先不要删。'),('然然后再检查。','然后再检查。')]:self.assertEqual(prepare_transcript(source)[0],expected)
 def test_emphasis_distributive_and_literals_not_deduplicated(self):
  for text in ['将就就好。','成就就来自持续投入。','你去那，那么我去这里。','就，就这样吧。','测试测试，好的好的，一个一个检查，真的真的很重要。','就是就是，这个方案可以。','他说“就就这这里”，请原样保留。','这个词是那那个，不要修改。']:
   self.assertEqual(prepare_transcript(text)[0],text)
 def test_none_is_verbatim(self):
  import worker
  text='请复测分段以后有没有漏字和重复。嗯，然后我想想。嗯，没没的。'
  self.assertEqual(worker.process(dict(models='/unused',text=text,words=[],cleanup='none'))['output'],text)
if __name__=='__main__':unittest.main()
