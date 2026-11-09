"""Private local timing summary. Never emits text, audio, IDs, vocabulary or paths."""
from pathlib import Path
import argparse,json,math,statistics
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--data-root',type=Path,default=Path.home()/'Library/Application Support/Dianyu')
p.add_argument('--last',type=int,default=30)
a=p.parse_args()
if not 1<=a.last<=10000:p.error('--last must be 1..10000')
records=json.loads((a.data_root/'sessions.json').read_text())
records=[r for r in records if r.get('source')=='microphone'and r.get('status')=='completed'and r.get('output')][:a.last]
def pick(meta,path):
 for key in path.split('.'):
  if not isinstance(meta,dict):return None
  meta=meta.get(key)
 return meta if isinstance(meta,(int,float))and not isinstance(meta,bool)and math.isfinite(meta)and meta>=0 else None
def metric(values):
 values=sorted(values)
 if not values:return {'样本数':0}
 # Nearest-rank P90; keep per-metric counts because old records lack fields.
 return {'样本数':len(values),'中位秒':round(statistics.median(values),4),'P90秒':round(values[max(0,math.ceil(len(values)*.9)-1)],4),'最大秒':round(max(values),4)}
rows=[]
for r in records:
 try:meta=json.loads(r.get('metadata')or'{}')
 except (ValueError,TypeError):continue
 rows.append((r.get('duration',0),meta))
metrics={'音频准备':'audio_prepare_seconds','识别全部复核':'asr_decode_seconds','整理':'cleanup_seconds','录音收尾':'recording_stop.actual_tail_seconds','停说到处理完成':'stop_to_processed_seconds','填入流程返回':'delivery_wall_seconds'}
result={'说明':'仅本机真实麦克风、已完成且有输出的最近记录。引导/回放测试排除；各字段缺失时不计入。填入流程返回不代表已验证填入。不同版本、设备与语言混合时不可当受控比较。','记录数':len(rows),'分组':[]}
for label,low,high in [('5秒以内',0,5),('5到12秒',5,12),('超过12秒',12,float('inf'))]:
 selected=[m for duration,m in rows if low<duration<=high];group={'录音长度':label,'记录数':len(selected)}
 for label,path in metrics.items():group[label]=metric([v for m in selected if(v:=pick(m,path))is not None])
 group['停说到验证填入']=metric([v for m in selected if m.get('delivery',{}).get('verified')is True and(v:=pick(m,'stop_to_delivery_seconds'))is not None])
 result['分组'].append(group)
print(json.dumps(result,ensure_ascii=False,indent=2))
