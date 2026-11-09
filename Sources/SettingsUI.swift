import SwiftUI
import AppKit
import ApplicationServices

enum DianyuSettingsStyle {
    static let inset:CGFloat=24
    static let sectionGap:CGFloat=24
    static let rowMinimum:CGFloat=55
    static let cardRadius:CGFloat=12
}
struct PreferenceCard<Content:View>:View {
    let title:String
    var detail=""
    @ViewBuilder var content:()->Content
    var body:some View{
        VStack(alignment:.leading,spacing:10){
            VStack(alignment:.leading,spacing:4){Text(title).font(.system(size:14,weight:.semibold));if !detail.isEmpty{Text(detail).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}}
            VStack(spacing:0,content:content).background(DianyuDesign.group,in:RoundedRectangle(cornerRadius:15))
        }
    }
}
struct PreferenceRow<Control:View>:View {
    let title:String
    var detail=""
    let symbol:String
    @ViewBuilder var control:()->Control
    var body:some View{
        HStack(spacing:14){
            HStack(spacing:12){
                Image(systemName:symbol).font(.system(size:17)).foregroundStyle(DianyuDesign.secondary).frame(width:22).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:3){Text(title).font(.system(size:13,weight:.semibold));if !detail.isEmpty{Text(detail).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}}.frame(maxWidth:.infinity,alignment:.leading)
            }
            control().fixedSize(horizontal:true,vertical:false)
        }.frame(maxWidth:.infinity,minHeight:32,alignment:.leading).padding(.horizontal,14).padding(.vertical,8)
    }
}
struct PreferenceDivider:View{var body:some View{Rectangle().fill(DianyuDesign.line).frame(height:1).padding(.leading,52).padding(.trailing,18)}}
struct PreferenceSwitch:View {
    let title:String
    var detail=""
    let symbol:String
    @Binding var value:Bool
    var body:some View{PreferenceRow(title:title,detail:detail,symbol:symbol){Toggle(title,isOn:$value).labelsHidden().toggleStyle(SwitchToggleStyle(tint:DianyuDesign.accent)).controlSize(.small)}}
}
struct PermissionStatus:View {
    var body:some View{HStack(spacing:6){Image(systemName:"checkmark").font(.system(size:9,weight:.bold)).foregroundStyle(.white).frame(width:18,height:18).background(.green,in:Circle());Text("已授权").font(.system(size:12))}.foregroundStyle(DianyuDesign.secondary).accessibilityElement(children:.combine)}
}
struct SettingsPage:View {
    @ObservedObject var app:AppState
    let section:String
    @ObservedObject private var updates=UpdateManager.shared
    @AppStorage(DianyuDesign.appearanceKey) private var appearance="system"
    @AppStorage(CorrectionLearning.preferenceKey) private var suggestCorrections=true
    private enum ScrollTarget:Hashable{case top}
    var body:some View{
        ScrollViewReader{proxy in
            ScrollView{
                VStack(alignment:.leading,spacing:18){
                    switch section {
                    case "录音":recording
                    case "快捷键":ShortcutSettingsPage(app:app)
                    case "权限":permissions
                    case "关于":about
                    default:general
                    }
                }.padding(.leading,20).padding(.trailing,24).padding(.bottom,20).frame(maxWidth:.infinity,alignment:.leading).id(ScrollTarget.top)
            }.onChange(of:section){_,_ in proxy.scrollTo(ScrollTarget.top,anchor:.top)}
        }.font(.system(size:13)).disabled(app.busy)
        .onChange(of:app.store.preferences){_ in app.applyPreferences()}
        .onChange(of:suggestCorrections){value in if !value{app.stopCorrectionLearning()}}
    }
    private var general:some View{
        Group{
            PreferenceCard(title:"外观",detail:"跟随 macOS，或为咸鱼说单独选择外观。"){
                PreferenceRow(title:"应用外观",detail:"导航材质与内容对比度会一同适配。",symbol:"circle.lefthalf.filled"){
                    FlatSegmented(label:"应用外观",selection:$appearance,options:[("跟随系统","system"),("浅色","light"),("深色","dark")]).frame(width:250)
                }
            }
            PreferenceCard(title:"输出与恢复",detail:"先保存结果，再尝试填入。没有光标时也可以找回。"){
                PreferenceSwitch(title:"自动填入",detail:"有可用输入位置时，将结果写入当前应用。",symbol:"text.cursor",value:$app.store.preferences.autoPaste)
                PreferenceDivider()
                PreferenceSwitch(title:"保留到剪贴板",detail:"处理中若复制了新内容，不覆盖你的剪贴板。",symbol:"doc.on.clipboard",value:$app.store.preferences.keepClipboard)
                PreferenceDivider()
                PreferenceSwitch(title:"改字后建议加入词表",detail:"填入后3分钟内，检测同一输入框的局部改字，停顿后由你确认；已有词不重复提示，检测上下文不落盘。",symbol:"text.badge.plus",value:$suggestCorrections)
            }
            PreferenceCard(title:"本地记录"){
                PreferenceRow(title:"录音保留时间",detail:"仅清理已完成录音；文字和中断任务会保留。",symbol:"clock.arrow.circlepath"){
                    FlatMenuPicker(label:"录音保留时间",selection:$app.store.preferences.retentionDays,options:[("7 天",7),("30 天",30),("90 天",90),("一直保留",0)]).frame(width:132)
                }
                PreferenceDivider()
                PreferenceRow(title:"资料文件夹",detail:"模型、个人词表与历史独立保存在本机。",symbol:"folder"){
                    Button("打开文件夹"){NSWorkspace.shared.open(AppPaths.root)}
                }
            }
            PreferenceCard(title:"启动与后台"){
                PreferenceSwitch(title:"隐藏 Dock 图标",detail:"关闭窗口后继续在菜单栏运行；菜单栏中的“退出咸鱼说”会真正结束进程。",symbol:"menubar.rectangle",value:$app.store.preferences.hideDockIcon)
                PreferenceDivider()
                PreferenceSwitch(title:"登录时启动",detail:"登录这台 Mac 后，让咸鱼说在菜单栏准备就绪。",symbol:"power",value:Binding(get:{app.store.preferences.launchAtLogin},set:{app.setLogin($0)}))
            }
        }
    }
    private var recording:some View{
        Group{
            PreferenceCard(title:"录音设备"){
                PreferenceRow(title:"麦克风",detail:"设备断开时会保留当前录音。",symbol:"mic"){
                    FlatMenuPicker(label:"录音设备",selection:$app.store.preferences.microphoneUID,options:[("跟随系统默认","")]+app.microphones.map{($0.name,$0.id)}).frame(width:190)
                }
                PreferenceDivider()
                PreferenceSwitch(title:"优先内置麦克风",detail:"跟随系统默认时，优先选择 Mac 内置麦克风。",symbol:"laptopcomputer",value:$app.store.preferences.preferBuiltIn)
                PreferenceDivider()
                PreferenceSwitch(title:"保留耳机音乐控制",detail:"使用蓝牙耳机时，空闲期间释放麦克风，避免音乐按压被当作通话静音。录音期间耳机按压仍由 macOS 处理。",symbol:"headphones",value:$app.store.preferences.preserveHeadphoneControls)
                PreferenceDivider()
                PreferenceSwitch(title:"麦克风保温",detail:"减少起录等待；保护耳机音乐控制时暂停保温，睡眠和退出时停止。",symbol:"waveform",value:$app.store.preferences.keepMicWarm)
                PreferenceDivider()
                PreferenceSwitch(title:"边录边识别",detail:"长录音在自然停顿时提前处理，减少结束后的等待；完整原音仍会保留。",symbol:"bolt",value:$app.store.preferences.streamWhileRecording)
            }
            HStack(alignment:.top){VStack(alignment:.leading,spacing:5){Text(app.microphoneStatus);Text(app.microphoneRoute)}.font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true);Spacer();Button("刷新设备"){app.refreshDevices();app.applyPreferences()}}
            PreferenceCard(title:"录音时静音",detail:"开始录音时暂时关闭系统输出声音，结束或取消后恢复；麦克风保温时不静音。"){
                PreferenceSwitch(title:"录音时自动静音",detail:"音乐继续播放，录音期间听不到系统输出声音。",symbol:"speaker.slash",value:$app.store.preferences.muteWhileRecording)
            }
            if app.store.preferences.muteWhileRecording{Text(app.outputMuteStatus).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
            PreferenceCard(title:"说话方式"){
                PreferenceSwitch(title:"按住说话",detail:"开启后松开结束；关闭时，按一次开始、再按一次结束。",symbol:"hand.tap",value:$app.store.preferences.holdToTalk)
            }
            Text("录音中按 Esc 取消，内容仍保留在历史。开启保温后，系统的麦克风指示灯可能持续显示。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var permissions:some View{
        Group{
            PreferenceCard(title:"系统权限",detail:"仅使用录音与填入文字需要的权限。"){
                PreferenceRow(title:"麦克风",detail:"录制你主动开始的语音输入。",symbol:"mic"){
                    if Recorder.authorized{PermissionStatus()}else{Button("去授权"){app.openPrivacy("Privacy_Microphone")}}
                }
                PreferenceDivider()
                PreferenceRow(title:"辅助功能",detail:"跨应用填入文字，以及右侧 Option / Fn 快捷键。",symbol:"accessibility"){
                    if AXIsProcessTrusted(){PermissionStatus()}else{Button("去授权"){app.requestAccessibility()}}
                }
            }
            HStack{Text("无需屏幕录制、系统音频或日历权限。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary);Spacer();Button("打开系统权限设置"){app.openPrivacy("Privacy_Accessibility")}}
        }
    }
    private var about:some View{
        Group{
            HStack(spacing:18){BrandMark(size:52);VStack(alignment:.leading,spacing:6){Text("咸鱼说").font(.system(size:24,weight:.bold));Text("把想法，说出来。").font(.system(size:13)).foregroundStyle(DianyuDesign.secondary)};Spacer();Text(DianyuDesign.version).font(.system(size:13)).foregroundStyle(DianyuDesign.secondary)}.padding(22).background(DianyuDesign.feature,in:RoundedRectangle(cornerRadius:15))
            PreferenceCard(title:"版本与更新"){
                PreferenceRow(title:"当前版本",detail:"独立本机测试版",symbol:"app"){
                    Text(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString")as?String ?? "").foregroundStyle(DianyuDesign.secondary)
                }
                PreferenceDivider()
                PreferenceRow(title:"应用更新",detail:"更新保留本地模型、词表和历史。",symbol:"arrow.down.circle"){
                    Button("检查更新"){updates.check()}
                }
            }
            Text(updates.status).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
            PreferenceCard(title:"使用引导"){PreferenceRow(title:"重新体验首次设置",detail:"权限、本地模型、快捷键和试说；保留现有配置。",symbol:"sparkles"){Button("开始引导"){app.startOnboarding()}}}
            PreferenceCard(title:"隐私"){
                PreferenceRow(title:"全部在本机处理",detail:"无需账号或 API Key，不上传录音或文字。",symbol:"lock.shield"){Text("本地").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
            }
            Text("本版使用固定本地签名，尚未完成 Apple Developer ID 公证与另一台 Mac 的安装验证。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
struct ShortcutSettingsPage:View {
    @ObservedObject var app:AppState
    var onCapture:(Bool)->Void={_ in}
    @UIState private var selected=1
    @UIState private var active:Int?
    @UIState private var pressed:[String]=[]
    @UIState private var message=""
    private var current:KeyBinding{selected==2 ? app.store.preferences.translation:app.store.preferences.dictation}
    var body:some View{
        VStack(alignment:.leading,spacing:24){
            KeycapStrip(keys:pressed.isEmpty ? current.keycaps:pressed,pressed:!pressed.isEmpty,large:true).frame(maxWidth:.infinity).frame(height:88)
            PreferenceCard(title:"全局快捷键",detail:"点击一行预览，点击右侧快捷键框开始录制。松开后立即保存。"){
                row("开始 / 结束听写",symbol:"mic",id:1)
                PreferenceDivider()
                row("直接出英文",symbol:"character.bubble",id:2)
            }
            HStack(alignment:.top,spacing:16){
                Text(message.isEmpty ? active==nil ? "支持组合键、F1–F12、独立右侧 Option 或 Fn。录制时按 Esc、点击外部、切换窗口或离开页面取消。":"正在录制：按下所需按键，松开保存；Esc 或点击其他位置取消。":message)
                    .font(.system(size:12)).foregroundStyle(active != nil ? DianyuDesign.accent:DianyuDesign.secondary).frame(maxWidth:.infinity,minHeight:42,maxHeight:42,alignment:.topLeading)
                Button("恢复默认"){app.store.preferences.dictation=KeyBinding();app.store.preferences.translation=Preferences().translation;app.applyPreferences();message="快捷键已恢复默认并保存。"}.disabled(active != nil)
            }
            if !app.shortcutError.isEmpty{Text(app.shortcutError).font(.system(size:12)).foregroundStyle(.orange)}
        }.onDisappear{app.pauseShortcutCapture(false);active=nil;pressed=[];onCapture(false)}
    }
    private func row(_ title:String,symbol:String,id:Int)->some View{
        PreferenceRow(title:title,symbol:symbol){
            InlineShortcut(binding:id==2 ? app.store.preferences.translation:app.store.preferences.dictation,selected:selected==id,
                onBegin:{selected=id;active=id;pressed=[];message="";app.pauseShortcutCapture(true);onCapture(true)},
                onEnd:{if active==id{active=nil;pressed=[];app.pauseShortcutCapture(false);onCapture(false)}},
                onPreview:{if active==id{pressed=$0}},onCommit:{assign($0,id:id)})
                .frame(width:116,height:32)
                .contextMenu{
                    Button("右侧 Option"){_=assign(KeyBinding(),id:id)}
                    Button("Fn"){_=assign(KeyBinding(key:63,modifiers:0,standalone:"fn",label:"Fn"),id:id)}
                    Button("恢复此项默认"){_=assign(id==2 ? Preferences().translation:KeyBinding(),id:id)}
                }
        }.background(selected==id ? Color.primary.opacity(0.045):Color.clear,in:RoundedRectangle(cornerRadius:10))
        .contentShape(Rectangle()).onTapGesture{if active==nil{selected=id;pressed=[]}}
    }
    private func assign(_ binding:KeyBinding,id:Int)->Bool{
        let other=id==2 ? app.store.preferences.dictation:app.store.preferences.translation
        guard !binding.matches(other)else{message="听写与翻译快捷键不能相同，请换一个。";return false}
        if id==2{app.store.preferences.translation=binding}else{app.store.preferences.dictation=binding}
        app.applyPreferences();message="快捷键已生效并保存。";return true
    }
}
