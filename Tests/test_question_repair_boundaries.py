import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import unittest
from transcript_rules import prepare_transcript

class QuestionRepairBoundaries(unittest.TestCase):
 def test_confirmation_and_attributive_clauses_do_not_retract_names(self):
  for text in ['发给小王，不对吗？','联系人是小王，不对吧？','地点是上海，不对呢？','我说的是小王，不对的地方是日期。','发给小王，不对啊？','发给小王，不对呀。','请发给小王不对吗？']:
   with self.subTest(text=text):self.assertEqual(prepare_transcript(text)[0],text)
 def test_requests_and_questions_are_not_new_entity_values(self):
  for tail in ['能不能确认一下？','请帮我核对一下。','帮忙确认。','是不是小李？','是否需要核对？','有没有写错？','怎么确认？','哪位联系人？']:
   text='发给小王，不对，'+tail
   with self.subTest(text=text):self.assertEqual(prepare_transcript(text)[0],text)
 def test_explicit_names_and_interjected_repairs_still_work(self):
  for source,want in [('发给小王，不对，小李。','发给小李。'),('发给小王，不对啊，是小李。','发给小李。'),('联系人是小王，不对，最终改成小李。','联系人是小李。'),('我要说的是同意，不对，改成不同意。','我要说的是不同意。')]:
   with self.subTest(source=source):self.assertEqual(prepare_transcript(source)[0],want)

if __name__=='__main__':unittest.main()
