import unittest,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import cleanup_pipeline as c
class ShortLatencyTests(unittest.TestCase):
 def test_clean_short_retains_text_and_avoids_model(self):
  for text in ['如果明天还没有收到付款，就先不要发货。','请帮我检查一下这个文档的内容。','这个单词是 thief，不是 theft。','这是无光标输入测试，请保留这句话。','明天下午三点把这个文件发给客户。','请检查 design.md 里面的设置项。']:
   with self.subTest(text=text):
    value,meta=c.cleanup(None,text,['thief','theft','C','design.md'])
    self.assertEqual(value,text);self.assertFalse(meta['used_model']);self.assertEqual(meta['reason'],'already_clean_short')
 def test_editing_hazards_do_not_use_complete_short_path(self):
  for text in ['嗯，请帮我检查一下这个文件的内容。','请帮我检查检查这个文档的内容。','先发正式版，不对，改成先发预览版。','为什么这个文件不能正常保存。','然后打开浏览器检查一下内容。','请把这个目录的内容，那个，重新整理一下。','先给客户发正式版，等等，我想改成先发预览版，正式版下周再说。','保留原话“先不要发货，然后联系客户”。','请帮我检查一下这个文件的内容']:
   with self.subTest(text=text):self.assertFalse(c.already_clean_short(text))
 def test_none_still_verbatim(self):
  import worker
  worker.send=lambda _:None
  raw='嗯，帮我检查检查这个文档的内容。'
  r=worker.process(dict(models='/missing',text=raw,words=['thief','C'],cleanup='none'))
  self.assertEqual(r['output'],raw)
if __name__=='__main__':unittest.main()
