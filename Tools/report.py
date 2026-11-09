from pathlib import Path
import json,csv,hashlib,subprocess,datetime,collections,zipfile
R=Path(__file__).resolve().parents[1];OUT=R.parents[1]/'outputs';B=R/'build'
def read(path):return json.loads(path.read_text())
rows=[json.loads(s)for s in (B/'acceptance/results.jsonl').read_text().splitlines()]
human_cases={r['id']:r for r in read(B/'human-private/cases.json')}
for row in read(B/'bundled-smoke.json'):
    row.setdefault('input',human_cases.get(row['id'],{}).get('reference',''))
    row.setdefault('category','真人原声回归'if row['kind']=='human'else'结构化分段专项')
    rows.append(row)
old_rows={(r['kind'],r['id']):r for r in map(json.loads,(B/'acceptance-v012/results.jsonl').read_text().splitlines())}
assert all(r['pass']==old_rows[(r['kind'],r['id'])]['pass'] and r['result'].get('output')==old_rows[(r['kind'],r['id'])]['result'].get('output') for r in rows if (r['kind'],r['id']) in old_rows),'Regression output drifted'
rows.append(read(B/'latest-user-regression.json'))
frozen=read(B/'acceptance/freeze.json');engine=Path('/Applications/点语.app/Contents/Resources/Engine')
assert all(hashlib.sha256((engine/name).read_bytes()).hexdigest()==sha for name,sha in frozen['engine_files'].items())
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict','/Applications/点语.app'],check=True)
baseline=read(B/'openwhispr-baseline.json')
assert all(hashlib.sha256(Path(name).read_bytes()).hexdigest()==sha for name,sha in baseline.items()),'Original OpenWhispr drifted'
summary={}
for kind in dict.fromkeys(r['kind']for r in rows):
    subset=[r for r in rows if r['kind']==kind and not r.get('diagnostic_only')]
    summary[kind]={'total':len(subset),'passed':sum(r['pass']for r in subset),'failed':sum(not r['pass']for r in subset)}
sessions=read(Path.home()/'Library/Application Support/Dianyu/sessions.json')
old_ids={r['id']for r in read(B/'native-before-warm-fix.json')}
final_voice=[r for r in sessions if r['id']not in old_ids and r['source']=='microphone' and 'thief'in r['output'].casefold() and 'theft'in r['output'].casefold() and r['status']=='completed']
receipt=read(B/'native-ui-receipt.json')if(B/'native-ui-receipt.json').exists()else{}
native=dict(earlier_effective_voice_inputs=4,earlier_empty_capture_failures=3,earlier_effective_voice_dictionary_checks=read(B/'native-dictionary-verification.json'),warm_capture_after_fix=read(B/'warm-capture-observation.json'),final_voice_after_fix=[{k:r[k]for k in ['id','raw','output','duration','delivery','processingSeconds']}for r in final_voice],ui_receipt=receipt)
updates=read(B/'update-integration/result.json');upgrade=read(B/'upgrade-after.json')
names={'light-text':'轻整理文字','none-text':'不整理文字','structured-text':'结构化文字','audio':'合成音频到最终正文','translation':'直接中译英','human':'既有真人录音','structured-special':'结构化专项','current-human':'新增真人实录'}
notes=[
 '这是本机可使用的独立测试版，不是已完成Developer ID公证与跨设备验证的正式发行版。原OpenWhispr程序、模型服务配置和启动项的校验值保持不变。',
 '基础复测1236条：875轻整理文字、52不整理、25结构化、266合成音频、4翻译、11既有真人录音、3结构化专项。另新增1条用户实际右Option录音，总计1237条；新增实录中的theft识别成set，记为失败。单元与系统流程测试另计。',
 '合成音频中14条此前预标为声学同音诊断，单列而不进入严格拼写分母；严格252条通过222条。所有结果仍在明细中。',
 '875条轻整理文字与266条音频的逐例通过/失败状态，与上一轮冻结的OpenWhispr本地后端最终报告一致；新界面没有自动提高模型识别率。',
 '既有真人11份来自同一人7条原始录音，包含切片。长停顿的完整英文录音仍失败，不能称为11个独立说话人的测试。',
 '结构化整理先轻整理，再将语义边界映射回原文。只调整段落或明确枚举的布局，保护引用、代码、路径和网址；不允许增加标题、事实或总结。短输入可以保持原样。',
 '不整理档位直接保留ASR文本，不运行文字准备规则或整理模型；个人词表仍进入ASR。52条逐字检查包括空白、重复和改口原话。',
 '个人词表从原应用只读导入为独立副本，新增、编辑、移除及升级保存已在真实界面验证。临时DianyuQA词已移除，恢复原有10词。',
 '6条有效实录的实际解码调用均收到完整会话词表，摘要与录音开始时的词表快照一致。词表提示会提高相关词的召回，不能保证每个发音都识别正确。',
 '初版保温期间出现3次零音频任务，判为失败并保留。修复后增加持续音频拉取、避免App Nap、实际首帧检查和陈旧流重建；后续采集验证写入了真实音频字节。',
 '无光标结果既保留在历史，也实际通过系统剪贴板粘贴进TextEdit。不能把仅有API成功当作此项通过。',
 '曾发现Python缓存写入应用包导致资源签名失效，已禁止包内字节码缓存写入；真实模型推理后再次执行严格递归签名校验通过。',
 '已做同路径、固定签名的0.1.0→0.1.1→0.1.2→0.1.3替换与重开，麦克风和辅助功能显示仍可用，整理档位、词表和历史保留。实际权限操作与系统开关分开验证。',
 '真实Sparkle下载、坏包拒绝、安装就绪回调、替换、重启和数据标记保留，在独立后台测试应用中通过。测试只用临时回环HTTP；正式应用只接受HTTPS发布源，尚未配置或发布线上更新。',
 '未验证另一台Mac、整机重启、所有系统版本、物理Fn及每一种按住说话组合、所有蓝牙设备断连场景；这些没有被计入已通过项。',
 '本轮新增启动时ASR预热、空闲保留ASR、细分音频准备/模型加载/解码耗时；模型权重、词表提示和解码参数保持一致。预热本身约2.35秒，在应用启动时完成，不计入录音后的识别时间。',
 '新版录音浮窗默认128×32点；点击展开详情或恢复，成功填入后自动隐藏。右侧Option为默认听写键，支持键帽预览、实际按键录入、冲突检查和恢复默认。',
 '快捷键变更与默认迁移、40项资料/快捷键状态检查、10组worker检查和7项更新策略检查通过。自动化工具不能单独按修饰键，物理按键以系统验收记录为准。',
 '最新5.4秒真人录音在后台批测并发且首次使用整理模型时，ASR3.45秒、整理5.64秒，总9.23秒；停止点语批测后的实际应用重试为ASR1.39秒、整理2.49秒，总4.19秒。该差异含并发负载和模型冷加载影响，不能全部归因于ASR预热；两次均把theft错识为set。',
 '三条同一长录音另做计时：约60秒录音预热后识别8.22–9.26秒；25秒约3.08–3.41秒；19秒约2.18–2.53秒。原版已暖模型的60秒识别约9.24秒，因此本轮主要移除了冷加载，并没有显著缩短长句的暖态解码。时延样本很少，不计入准确率分母。',
 '按最新反馈将麦克风首帧等待移出主线程；准备阶段立刻显示胶囊，白色高对比点阵、录音计时、识别/整理阶段与等待秒数持续可见。此版已经实际采集、取消与重试验证，主观安全感仍需用户继续评价。',
 '当前长录音仍在结束后整段识别，尚未实现边录边识别。录音上限10分钟；更长内容需分段。',
 '统计只计成功且有文字的麦克风输入，重试沿用同一记录编号，文件导入和文本测试不计入使用量；中文按字、英文数字按词计。',
 '运行环境包含在应用内，模型独立保存在Dianyu资料目录。此安装包不含模型、个人词表、历史、私人录音或签名私钥；其他电脑需导入对应模型文件。',
]
data=dict(date='2026-11-04',app='点语0.1.3',summary=summary,native=native,updates=updates,upgrade=upgrade,upgrade_v013=read(B/'upgrade-v013-after.json'),notes=notes,rows=rows,package=read(OUT/'点语安装包校验.json'),engine_freeze=frozen,latency_before=read(B/'latency-before.json'),latency_after=read(B/'latency-after.json'),latency_long=read(B/'latency-long.json'),latest_user_timing=read(B/'latest-user-timing.json'),acceptance=read(B/'native-final-acceptance.json'))
(OUT/'点语完整测试数据.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
with(OUT/'点语完整测试明细.csv').open('w',encoding='utf-8-sig',newline='')as f:
    writer=csv.writer(f);writer.writerow(['类型','编号','分类','输入','原始识别','最终结果','通过','同音诊断单列','未通过原因'])
    for row in rows:
        result=row['result'];writer.writerow([names[row['kind']],row['id'],row.get('category',''),row.get('input',''),result.get('raw',''),result.get('output',''),row['pass'],bool(row.get('diagnostic_only')),json.dumps(row.get('failures',[]),ensure_ascii=False)])
text=['点语0.1.3 本地测试版｜2026-11-04','','当前状态：已独立安装，三档整理、词表、统计、录音与翻译可使用。不是已公证正式发行版。','']
for kind,s in summary.items():text.append(f"{names[kind]}：{s['passed']}/{s['total']}通过；{s['failed']}未通过。")
text+=['','系统与实录验收：']
for key,value in receipt.items():text.append(key+'：'+str(value))
text+=['','方法与边界：']+[str(i+1)+'. '+note for i,note in enumerate(notes)]
(OUT/'点语测试与使用说明.txt').write_text('\n'.join(text))
manual='''点语0.1.3｜使用说明

已安装位置：/Applications/点语.app
听写：右侧Option / Alt。单独按一次开始，再按一次结束；左侧Option不触发。
直接出英文：Control+Option+Shift+Space。
取消：录音或处理中按Esc；已保存的内容可在历史中恢复。
设置中点击快捷键键帽，再按下所需按键，松开保存；可选择组合键、F1–F12、独立右Option/Fn，或按住说话。听写与翻译不能设为相同按键。独立修饰键需要辅助功能可用，实际可用性依键盘与系统而定。

不整理：直接保留原始识别，个人词表仍参与识别。
轻整理：去无意义重复、停顿和明确改口，补标点；默认推荐。
结构化整理：先轻整理，再按语义组织段落或明确枚举，不总结、不补写。极短内容可以不分段。

个人词表：原有10词已导入独立副本。可增删改、启用/停用、导入导出。每次录音冻结一份词表，新增项从下一次任务生效。最多128项，每项80字，超过会提示，不静默丢弃。
历史：保留原音、原始识别、整理结果和译文，可回放、复制、重试和查看词表验证记录。
无光标：先保存结果，再尝试填入；无法填入时保留在历史和浮窗，并在剪贴板未被新内容替换时复制。定位后按Command+V即可。
小胶囊：录音时以128×32点浮窗显示白色实时点阵与录音计时；按键后先显示准备状态，识别和整理时持续显示阶段及等待秒数；点击结束录音，处理完成后可点击展开复制或恢复；成功填入后自动隐藏。
识别预热：应用启动时提前加载并预热识别模型，保持识别模型就绪以减少首次等待。退出应用释放，整理与翻译模型空闲时可释放。取消或异常停止模型进程后，下次开始录音时会提前重启预热。
麦克风保温：设置中可开关。保温会持续占用麦克风；未录音时不写音频文件。睡眠或退出时停止。
统计：中文按字、英文与数字按词计；成功的麦克风输入计数，重试不重复统计，自测和导入不计入。

全部识别、整理和翻译在本机执行，不需要账号或API Key。当前模型为Qwen3-ASR-1.7B-8bit、Qwen3-1.7B-4bit整理和Hy-MT2-1.8B-4bit翻译。
独立资料目录：~/Library/Application Support/Dianyu。应用更新保留此目录。模型与原OpenWhispr通过独立文件复用，没有改动旧应用的程序、配置、热键和服务。

此ZIP包含应用与运行环境，不包含模型或你的私人资料。另一台Apple Silicon Mac需要导入对应的三个模型文件夹，可在“模型资源”页操作并校验。模型不用随每次应用更新重新下载。
本版使用固定本地自签名身份。对外正常分发仍需Apple Developer ID、公证与第二台Mac验证；不要通过关闭系统保护来代替这些步骤。正式HTTPS更新源尚未发布，检查更新会如实提示。

长录音目前在结束后整段处理，上限10分钟。复杂语义改口、英文近音和长停顿录音仍有已知失败，详见完整测试报告。
'''
(OUT/'点语使用说明.txt').write_text(manual)
payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('</','<\\/')
template=(R/'Tools/report.template.html').read_text()
(OUT/'点语完整测试报告.html').write_text(template.replace('__DATA__',payload))
print('Report generated:',len(rows),'inputs; final voice confirmation:',len(final_voice))
