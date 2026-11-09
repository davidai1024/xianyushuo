import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import unittest
from cleanup_pipeline import validate,should_bypass,malformed_disposals,restore_disposal_objects
from transcript_rules import prepare_transcript
class ArchiveRegressions(unittest.TestCase):
 def test_restriction_stays_attached_to_its_action_and_object(self):
  for action in ['删除缓存','保留原件','修改标题','开放预览','支持英文','提供摘要','处理当前任务','支付尾款','发送附件']:
   source='请只'+action+'。'
   self.assertEqual(validate(source,'请'+action+'。')[1],'restriction_scope_changed')
   self.assertNotEqual(validate(source,'请仅'+action+'。')[1],'restriction_scope_changed')
   self.assertTrue(validate(source,source)[0])
  self.assertEqual(validate('只删除缓存，保留原件。','删除缓存，只保留原件。')[1],'restriction_scope_changed')
  self.assertEqual(validate('应该保留原件，只删除缓存。','应该保留原件，删除缓存。')[1],'restriction_scope_changed')
 def test_animal_counter_is_not_a_restrictive_action(self):
  for text in ['一只猫在沙发上。','两只狗跑过来。','有一只提供陪伴的小狗。']:
   self.assertTrue(validate(text,text)[0])
 def test_explicit_attribution_is_not_changed_into_a_topic(self):
  self.assertEqual(validate('但是是你说的，是不是应该负责？','但是你所说的，是不是应该负责？')[1],'attribution_scope_changed')
  self.assertTrue(validate('这件事是你说的。','这件事是你亲口说的。')[0])
 def test_atomic_chinese_kept_out_of_editor(self):
  for text in ['好','嗯','试试','你试试','哈哈哈','我看看']:
   self.assertTrue(should_bypass(text))
 def test_normal_reduplication_is_not_a_stutter(self):
  for text in ['你试试。','你看看。','慢慢来。','刚刚说的。','谢谢。','听听看。','再想想。']:
   self.assertTrue(should_bypass(text));self.assertEqual(prepare_transcript(text)[0],text)
 def test_new_missing_disposal_object_is_rejected(self):
  for verb in ['存到','放到','写到','发给','传到','移到','删掉','改成','复制到','粘贴到','添加到','保存到','整理成','翻译成']:
   self.assertEqual(validate('请把这个'+verb+'目标里。','请把'+verb+'目标里。')[1],'disposal_object_lost')
 def test_valid_nominalized_object_is_allowed(self):
  for text in ['把存到银行卡里的钱取出来。','把发给他的文件撤回。','把放到桌上的东西收起来。']:
   self.assertEqual(malformed_disposals(text),0)
 def test_calendar_self_correction(self):
  cases=[('会议是六月二十四号，不对，改成七月二十五号。','会议是七月二十五号。'),('账期是2026年6月24日，不对，应该是2026年7月25日。','账期应该是2026年7月25日。'),('从六六月二十四号就有，不对，应该是六月二十四号。','应该从六月二十四号就有。'),('时间应该是六月24号，不对，应该是七月25号。','时间应该是七月25号。')]
  for raw,want in cases:self.assertEqual(prepare_transcript(raw)[0],want)
 def test_calendar_narrative_literal_negation_and_duration_preserved(self):
  for text in ['六月24号开会，七月25号交付。','请把会议从六月24号更正为七月25号。','以前定六月24号，后来改七月25号，记录变更过程。','不是六月24号，不对，应该是七月25号。','需要三个月，不是两个月。','请原样保留“六月24号，不对，改成七月25号”。']:
   self.assertEqual(prepare_transcript(text)[0],text)
 def test_source_object_restored_without_a_second_model_call(self):
  source='整理一下这个，把这个存到我的笔记里。';proposal='整理这个，把存到我的笔记里。'
  result,count=restore_disposal_objects(source,proposal)
  self.assertEqual(result,'整理这个，把这个存到我的笔记里。');self.assertEqual(count,1);self.assertTrue(validate(source,result)[0])
 def test_ambiguous_or_quoted_source_object_never_guessed(self):
  for source in ['把甲存到笔记，把乙存到桌面。','原文是“把这个存到笔记”。']:
   proposal='把存到笔记。';self.assertEqual(restore_disposal_objects(source,proposal),(proposal,0))
 def test_nominalized_object_not_rewritten(self):
  text='把发给他的文件撤回。';self.assertEqual(restore_disposal_objects('把之前发给他的文件撤回。',text),(text,0))
if __name__=='__main__':unittest.main()
