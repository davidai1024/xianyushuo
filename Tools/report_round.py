"""Summarize a completed local replay round without exporting recordings or paths."""
from pathlib import Path
import argparse,collections,csv,hashlib,json,plistlib,statistics
p=argparse.ArgumentParser();p.add_argument('--round',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
R=a.round;O=a.output;O.mkdir(parents=True,exist_ok=True)
def rows(path):return [json.loads(x)for x in path.read_text().splitlines()]
expanded=rows(R/'final-expanded-final/results.jsonl');audio=rows(R/'final-audio/results.jsonl');text=rows(R/'main-regression/results.jsonl')
assert len(expanded)==218 and len(audio)==270
freeze=json.loads((R/'final-expanded-final/freeze.json').read_text())
for record in expanded:
 if record['variant']=='candidate':
  for segment in record['result'].get('metadata',{}).get('asr',{}).get('segments',[]):
   first=segment['decoder_calls'][0]
   assert first['hotwords_count']==10 and first['effective_dictionary_terms']==10
bundle=Path('/Applications/点语.app/Contents');info=plistlib.loads((bundle/'Info.plist').read_bytes())
for name,digest in freeze['engines']['candidate'].items():assert hashlib.sha256((bundle/'Resources/Engine'/name).read_bytes()).hexdigest()==digest
def score(group):return dict(total=len(group),passed=sum(x['pass']for x in group),failed=sum(not x['pass']for x in group))
summary={}
for variant in ['before','candidate']:
 selected=[r for r in expanded if r['variant']==variant and not r['diagnostic_only']]
 human=[r for r in selected if not r['id'].startswith('reverse_')]
 summary[variant]={'human_with_derivatives':score(human),'human_original_files':score([r for r in human if r['gain_db']==0]),'synthetic_reverse':score([r for r in selected if r['id'].startswith('reverse_')]),'fresh_eight':score([r for r in human if r['gain_db']==0 and r['id'].split('@')[0]in ['fresh_'+str(i)for i in range(1,8)]+['fresh_8_repeat']])}
old={r['id']:r for r in expanded if r['variant']=='before'}
changes=[dict(id=r['id'],before=old[r['id']]['result']['output'],after=r['result']['output'],before_pass=old[r['id']]['pass'],after_pass=r['pass'])for r in expanded if r['variant']=='candidate'and not r['diagnostic_only']and old[r['id']]['pass']!=r['pass']]
strict_audio=[r for r in audio if r['kind']=='audio'and not r.get('diagnostic_only')]
text_summary={k:score([r for r in text if r['kind']==k])for k in ['light-text','none-text','structured-text']}
data=dict(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],summary=summary,audio=score(strict_audio),translation=score([r for r in audio if r['kind']=='translation']),text=text_summary,changes=changes,regressions=[c for c in changes if c['before_pass']and not c['after_pass']],engine_sha256=freeze['engines']['candidate'],dictionary_count=len(freeze['candidate_words']),dictionary_sha256=hashlib.sha256(json.dumps(freeze['candidate_words'],ensure_ascii=False,separators=(',',':')).encode()).hexdigest(),limits=['One human speaker. Twenty-three source/cut files; four are cuts of one longer recording. Three gain conditions do not add independent utterances.','One uncertain original recording and its two gain derivatives are diagnostic only; the confirmed re-recording replaces it in strict scoring.','Synthetic bilingual splices are reported separately. Strict results describe these fixtures, not population accuracy.','875 text, 52 verbatim and 25 structured cases were completed with the identical cleanup files. Dictionary differences affect only the bypassed word clipboard, checked again in the final installed bundle.','Physical Codex fill was confirmed by the user on 0.1.5. Version 0.1.6 adds readback compatibility; its final physical hotkey/readback status has not been separately confirmed.'])
(O/'点语-0.1.6-复测数据.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
with(O/'点语-0.1.6-录音对照.csv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.writer(f);w.writerow(['样本','版本','来源分类','音量变化dB','仅诊断','参考内容','原始识别','最终结果','通过','识别秒数','整理秒数','失败原因'])
 for r in expanded:
  result=r['result'];m=result.get('metadata',{});w.writerow([r['id'],r['variant'],r['category'],r['gain_db'],r['diagnostic_only'],r['reference'],result.get('raw',''),result.get('output',''),r['pass'],m.get('asr_decode_seconds',''),m.get('cleanup_seconds',''),json.dumps(r['failures'],ensure_ascii=False)])
with(O/'点语-0.1.6-旧集回归.csv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.writer(f);w.writerow(['样本','类型','来源分类','输入参考','原始识别','最终结果','通过','仅诊断','失败原因'])
 for r in audio:
  result=r['result'];w.writerow([r['id'],r['kind'],r['category'],r['input'],result.get('raw',''),result.get('output',''),r['pass'],r.get('diagnostic_only',False),json.dumps(r['failures'],ensure_ascii=False)])
before=summary['before'];after=summary['candidate']
lines=[f"点语 {data['version']}（{data['build']}）本地修复与复测记录",'',
'已完成：轻整理去掉有明确边界的犹豫“嗯”；模型改写不安全时也保留这项去赘词结果，保留“请”、否定和事实。独立“嗯／嗯嗯”、肯定答复、引用和语气词讨论保守保留；不整理逐字保留。',
'自动填入：0.1.5已由用户确认真实进入Codex输入框。0.1.6补充网页段落换行与选区不可靠时的读回确认，要求结果确实新增；不以AX接口成功代替填入证据。最终版本没有再要求用户做一次物理按键验收。',
'数据获取核对：这次“无光标输入测试，请保留这句话”的确认重录已完整识别并保存，无法填入是另一个阶段的问题。新WAV为24kHz单声道，按实际采样率重采样到16kHz。原第8条本人记不清是否说过后半句，因此没有把缺少后半句直接当作录音丢失来评分。',
'识别：原音优先；撤回导致C变成“是”的首轮增益。短中英混输在约束和音频解码一致时重听，不把set强制替换成theft。新增set/clipboard/cache词条的实验出现副作用，最终保留原有10个词条；不新增模型。','',
'词表使用：最终扩展集每条首轮识别的10个启用词条均进入实际模型提示，记录了提示摘要和10/10覆盖数；整理只保护正文已有词条，不依据词表凭空补词。',
f"真人原声文件：{before['human_original_files']['passed']}/{before['human_original_files']['total']} → {after['human_original_files']['passed']}/{after['human_original_files']['total']}。",
f"真人及降音量派生：{before['human_with_derivatives']['passed']}/{before['human_with_derivatives']['total']} → {after['human_with_derivatives']['passed']}/{after['human_with_derivatives']['total']}。",
f"最新8条真人难例：{before['fresh_eight']['passed']}/8 → {after['fresh_eight']['passed']}/8，仍未达标。",
f"独立合成近音词反向例：{before['synthetic_reverse']['passed']}/40 → {after['synthetic_reverse']['passed']}/40。",
f"扩展集发现新增退步：{len(data['regressions'])}项。原有失败保留在明细，没有改参考答案或剔除失败项。",
f"旧音频严格集：{data['audio']['passed']}/{data['audio']['total']}；另14项既有歧义诊断样本单列。翻译事实检查：{data['translation']['passed']}/{data['translation']['total']}。",
f"文本整理：{text_summary['light-text']['passed']}/875；不整理：{text_summary['none-text']['passed']}/52；结构化：{text_summary['structured-text']['passed']}/25。整理规则文件与该完整运行一致；最终词表差异仅影响clipboard短词旁路，已在最终安装包复核。",
'单项规则检查：18个Python测试、41项数据/快捷键检查、17项自动填入读回检查通过。它们不等同于真人录音或物理按键测试。','',
'确认修复：旧真人“这个单词是thief，不是theft”及其降音量版本恢复正确；用户这次“输入框，嗯，写入验证，请保留这句话”去掉嗯且保留请。',
'仍失败：新录单独thief→C；单独theft仍可能多出A；theft/set句中set→sent；反向set/theft句仍可能同化；cache→catch；旧长停顿整段录音、另一条写入/写无近音仍不稳定。完整结果见CSV。',
'边界：只有一位真人说话者。23份原声/切段文件含4份同一长录音的切段，音量派生不是新真人样本；1条参考长度不确定的原录音及2条派生只做诊断，已用确认重录替代。降音量同时缩放语音和噪声，仅验证幅度鲁棒性，不等同真实远讲或低信噪比。合成拼接例不能代表真实人群准确率。',
'安装状态：已独立安装并启动；麦克风与辅助功能已授权；原有右侧Option、轻整理、麦克风保温与10词词表保留。签名仍为固定本地自签名，未经Apple公证。模型仍独立存于本机，不在应用ZIP中。',
'数据保护：33条原有历史与偏好保留；自测不计入20条现有麦克风输入统计；8个受保护OpenWhispr文件未改变。最终安装引擎与冻结复测源文件摘要逐个匹配。',
'速度：没有获得普遍提速证据。不确定短中英片段可能多次解码并增加等待；长录音不执行这类额外复听。回放与应用内自测有部分重叠，不把本轮耗时当作严格性能基准。','',
'本轮没有上传录音、没有添加模型、没有公开发布安装包。应用包、源码包、校验记录和本报告保存在同一outputs目录。']
(O/'点语-0.1.6-复测结论.txt').write_text('\n'.join(lines)+'\n')
print(json.dumps({k:data[k]for k in ['summary','audio','translation']},ensure_ascii=False))
