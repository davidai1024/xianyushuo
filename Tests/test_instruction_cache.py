"""Exercise cache trimming with a real tiny Qwen attention stack, no weights/data."""
import unittest,sys,copy
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'Engine'))
import mlx.core as mx
from mlx_lm.models.qwen3 import Model,ModelArgs
from mlx_lm.models.cache import make_prompt_cache
import cleanup_pipeline as c
class Tokenizer:
 def apply_chat_template(self,messages,**kw):
  # A deterministic character tokenizer, including role boundaries.
  text=''.join('<'+m['role']+'>'+m['content']+'</end>'for m in messages)
  if kw.get('add_generation_prompt'):text+='<assistant>'
  return [ord(x)%127 for x in text]
class CountingModel(Model):
 def __call__(self,tokens,cache=None):
  self.input_tokens=getattr(self,'input_tokens',0)+tokens.shape[1]
  return super().__call__(tokens,cache=cache)
class InstructionCacheTests(unittest.TestCase):
 def test_vocab_prefix_and_utterance_isolation(self):
  mx.random.seed(1337)
  model=CountingModel(ModelArgs(model_type='qwen3',hidden_size=32,num_hidden_layers=2,intermediate_size=64,num_attention_heads=2,rms_norm_eps=1e-6,vocab_size=128,num_key_value_heads=1,max_position_embeddings=4096,head_dim=16,tie_word_embeddings=True,rope_theta=10000))
  tokenizer=Tokenizer();common='Fixed dictation instructions; preserve words and meaning. '*3
  for i in range(9):
   messages=[dict(role='system',content=common+' Vocabulary: '+str(i)),dict(role='user',content='Synthetic example'),dict(role='assistant',content='Synthetic example.'),dict(role='user',content='PRIVATE-UTTERANCE-'+str(i))]
   before=getattr(model,'input_tokens',0)
   suffix,cache,hit=c.prefix_prompt(model,tokenizer,messages)
   consumed=model.input_tokens-before
   full=tokenizer.apply_chat_template(messages,add_generation_prompt=True)
   prefix=tokenizer.apply_chat_template(messages[:-1],add_generation_prompt=False)
   self.assertEqual(suffix,full[len(prefix):]);self.assertEqual(cache[0].offset,len(prefix))
   if i:self.assertLess(consumed,len(prefix))
   logits=model(mx.array([suffix]),cache=cache)
   direct=make_prompt_cache(model);expected=model(mx.array([full]),cache=direct)
   self.assertTrue(bool(mx.allclose(logits[:,-1,:],expected[:,-1,:],rtol=2e-4,atol=2e-4)))
   self.assertEqual(int(mx.argmax(logits[:,-1,:])),int(mx.argmax(expected[:,-1,:])))
   entries=model._dictation_prefixes;self.assertLessEqual(len(entries),4)
   # Generation only mutates a private copy; no user tokens enter any prefix.
   for tokens,base in entries.items():
    self.assertEqual(base[0].offset,len(tokens))
    needle=[ord(x)%127 for x in 'PRIVATE-UTTERANCE-']
    self.assertFalse(any(list(tokens[j:j+len(needle)])==needle for j in range(len(tokens))))
   before=copy.deepcopy([(key,base[0].offset)for key,base in entries.items()])
   _,repeat,repeat_hit=c.prefix_prompt(model,tokenizer,messages)
   self.assertTrue(repeat_hit);self.assertEqual(repeat[0].offset,len(prefix))
   self.assertEqual({key:offset for key,offset in before},{key:base[0].offset for key,base in model._dictation_prefixes.items()})
if __name__=='__main__':unittest.main()
