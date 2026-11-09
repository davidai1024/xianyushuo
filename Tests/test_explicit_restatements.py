import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import unittest
from transcript_rules import prepare_transcript

class ExplicitRestatements(unittest.TestCase):
 def test_final_claim_keeps_original_topic(self):
  self.assertEqual(prepare_transcript('我觉得这个版本可以上线，不对，我的意思是还不能上线，至少还要测一天。')[0],'我觉得这个版本还不能上线，至少还要测一天。')
  self.assertEqual(prepare_transcript('这批订单可以交付，不对，我的意思是不能交付。')[0],'这批订单不能交付。')
 def test_changed_condition_and_scope(self):
  pairs=[('今天先发货，不对，不是今天，是收到付款之后再发货。','收到付款之后再发货。'),('这个问题已经修好了，不对，只修了登录页，支付页还没有修。','只修了登录页，支付页还没有修。'),('先用本地模型，或者不对，先用云端试试，等本地模型优化好再切回来。','先用云端试试，等本地模型优化好再切回来。'),('这个文件可以删除，不对，应该保留原件，只删除缓存。','应该保留原件，只删除缓存。')]
  for source,want in pairs:self.assertEqual(prepare_transcript(source)[0],want)
 def test_multiple_explicit_slots(self):
  self.assertEqual(prepare_transcript('周一上午先发十份，刚才说错了，时间改成周三下午，数量改成二十份。')[0],'周三下午先发二十份。')
  self.assertEqual(prepare_transcript('预算两千，地点上海，不对，我说的是预算改成三千，地点还是上海。')[0],'预算三千，地点上海，地点还是上海。')
 def test_city_field_and_recipient_elision(self):
  self.assertEqual(prepare_transcript('会议是在上海，不对，我说错城市了，是苏州，时间还是周四。')[0],'会议是在苏州，时间还是周四。')
  self.assertEqual(prepare_transcript('先给客户发正式版，等等，我想改成先发预览版，正式版下周再说。')[0],'先给客户发预览版，正式版下周再说。')
 def test_english_explicit_self_restatement(self):
  for source,want in [('I said publish immediately. Sorry, I meant keep it as a draft until approval.','Keep it as a draft until approval.'),('I meant we should not launch today, sorry, launch only after security approval.','Launch only after security approval.')]:
   self.assertEqual(prepare_transcript(source)[0],want)
 def test_independent_earlier_facts_survive(self):
  source='附件需要两位审批人，今天先发货，不对，不是今天，是收到付款之后再发货。'
  self.assertEqual(prepare_transcript(source)[0],'附件需要两位审批人，收到付款之后再发货。')
 def test_old_negation_and_other_peoples_opinions_are_not_inherited(self):
  for actor in ['你觉得','他觉得','她认为','他们觉得','你们认为','']:
   for modal in ['不能','不可以','还不能','尚不能','未能','没有能力']:
    source=actor+'这个版本'+modal+'上线，不对，我的意思是还不能上线。'
    with self.subTest(source=source):self.assertEqual(prepare_transcript(source)[0],source)
  for actor in ['你觉得','他觉得','她认为','他们觉得','你们认为']:
   source=actor+'这个版本可以上线，不对，我的意思是不能上线。'
   self.assertEqual(prepare_transcript(source)[0],source)
 def test_ambiguous_historical_conditional_and_quoted_claims_survive(self):
  for source in ['以前今天先发货，不对，不是今天，是收到付款之后再发货。','如果这个文件可以删除，不对，应该保留原件。','他说这个问题已经修好了，不对，只修了登录页。','周一开会，周二发货，刚才说错了，时间改成周三。','预算两千，预算四千，不对，我说的是预算改成三千。','会议是在上海，活动在北京，不对，我说错城市了，是苏州。','请保留“先用本地模型，或者不对，先用云端”。','I said publish yesterday. Sorry, I meant keep the draft.','I meant launch today, sorry, the budget is unavailable.','今天先发货，不对，不是今天，是明天开会。','我觉得这个版本可以上线，不对，我的意思是他不能上线。','先给客户发正式版，等等，我想改成先给经理发预览版。']:
   with self.subTest(source=source):self.assertEqual(prepare_transcript(source)[0],source)

if __name__=='__main__':unittest.main()
