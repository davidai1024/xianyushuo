"""Orchestration/semantic boundaries with a stub generator, not model accuracy."""
import sys,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import cleanup_pipeline as c
class CapturingTokenizer:
 def __init__(self):self.messages=None
 def apply_chat_template(self,messages,**kw):self.messages=messages;return 'stub'
class SpeakMorePromptTests(unittest.TestCase):
 def run_stub(self,source,output,words=()):
  tokenizer=CapturingTokenizer()
  with patch.object(c.mlx_lm,'generate',return_value=output)as generate:
   result,meta=c.cleanup((object(),tokenizer),source,words)
  return result,meta,tokenizer,generate.call_count
 def test_full_vocabulary_reaches_actual_message(self):
  words=['term'+str(i)for i in range(128)];source='嗯，请保留这个文件的全部内容。'
  output,meta,tokenizer,calls=self.run_stub(source,'请保留这个文件的全部内容。',words)
  self.assertEqual(calls,1);self.assertEqual(meta['prompt_dictionary_count'],128)
  system=tokenizer.messages[0]['content']
  for word in words:self.assertIn('\n'+word,system)
  self.assertIn('<原文>',tokenizer.messages[-1]['content'])
 def test_conversational_grammar_is_not_bypassed(self):
  source='还有这个整理，感觉我整理的也不行。';want='还有这个整理，我感觉整理得也不行。'
  output,meta,_,calls=self.run_stub(source,want)
  self.assertFalse(c.already_clean_short(source));self.assertEqual(calls,1);self.assertEqual(output,want);self.assertTrue(meta['accepted'])
 def test_isolated_words_and_letters_are_not_rewritten(self):
  for text in ['C','theft','thief','嗯','design.md']:
   with self.subTest(text=text):
    output,meta,_,calls=self.run_stub(text,'incorrect')
    self.assertEqual(calls,0);self.assertEqual(output,text)
 def test_meaningful_repeated_acknowledgement_survives_model_edit(self):
  output,meta,_,calls=self.run_stub('好的好的','好的')
  self.assertEqual(calls,1);self.assertEqual(output,'好的好的');self.assertFalse(meta['accepted'])
 def test_literal_speech_does_not_enter_model(self):
  source='请原样保留“嗯，我我觉得不行”。'
  output,_,_,calls=self.run_stub(source,'不行。')
  self.assertEqual(calls,0);self.assertEqual(output,source)
 def test_marker_and_wrapper_cannot_replace_real_content(self):
  source='嗯，请保留这个文件的全部内容。'
  for candidate in ['<无人声>','<原文>请保留这个文件的全部内容。</原文>']:
   output,meta,_,_=self.run_stub(source,candidate)
   self.assertEqual(output,'请保留这个文件的全部内容。');self.assertFalse(meta['accepted'])
 def test_negative_and_actor_rewrites_still_fail(self):
  for source,candidate in [('嗯，如果还没付款，就不要发货。','如果付款，就发货。'),('嗯，她感觉我整理的文件不完整。','我感觉她整理的文件不完整。')]:
   output,meta,_,_=self.run_stub(source,candidate)
   self.assertFalse(meta['accepted'])
   if '付款'in source:self.assertIn('不要',output)
   else:self.assertIn('她感觉我',output)
 def test_none_mode_remains_verbatim(self):
  import worker
  source='嗯，我我觉得这个 set 可能不行。'
  with patch.object(worker,'send'),patch.object(worker,'load')as load:
   result=worker.process(dict(models='/missing',text=source,words=['C','theft'],cleanup='none'))
  load.assert_not_called();self.assertEqual(result['output'],source)
 def test_short_universal_action_is_not_discarded(self):
  source='嗯，我想要一个这个，一个那个，都保留。'
  output,meta,_,_=self.run_stub(source,'我想要一个这个，一个那个。')
  self.assertFalse(meta['accepted']);self.assertIn('都保留',output)
 def test_grammar_routing_preserves_literal_and_demonstrative_choices(self):
  for text in ['如何创建一个这个团队号？','昨天的修改的那段配置还需要保留。']:
   self.assertTrue(c.needs_grammar_repair(text));self.assertFalse(c.already_clean_short(text))
  for text in ['我想要一个这个，一个那个，都保留。','这个文件是昨天的，发给客户之前先检查一遍。','请原样输入一个这个。','原话是“昨天的发的那个通知”。']:
   self.assertFalse(c.needs_grammar_repair(text))
 def test_dictionary_relevance_checks_every_term_with_latin_boundaries(self):
  words=['C','cache','design.md']+['term'+str(i)for i in range(128)]
  self.assertEqual(c.matching_hints('请检查 design.md，清理 cache，保留 term127。',words),['cache','design.md','term127'])
 def test_remaining_stutter_uses_one_legacy_grammar_call(self):
  for text in ['请画一个九宫九宫格。','请在后后后面加上说明。','请准备一张这个封面。','请检查这个这个标题。']:
   self.assertTrue(c.needs_grammar_repair(text))
  for text in ['这个非常非常重要。','好的好的，没问题。','请一张一张地检查。','哈哈哈哈，真有意思。','请原样保留“九宫九宫格”。','一张这个，一张那个，都保留。']:
   self.assertFalse(c.needs_grammar_repair(text))
  output,meta,_,calls=self.run_stub('请画一个九宫九宫格。','请画一个九宫格。')
  self.assertEqual(calls,1);self.assertEqual(meta['profile'],'grammar');self.assertEqual(output,'请画一个九宫格。')
if __name__=='__main__':unittest.main()
