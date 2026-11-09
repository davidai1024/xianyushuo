import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

enum SetupStep:Int,Codable,CaseIterable {
    case welcome,permissions,models,shortcuts,practice,ready
    var label:String{["欢迎","系统权限","本地模型","快捷键","试说一句","准备好了"][rawValue]}
    var headline:String{["把想法，\n说出来。","只开启，\n需要的权限。","用到什么，\n再下载什么。","一个按键，\n开始和结束。","试着说，\n看见你的声音。","接下来，\n交给你的声音。"][rawValue]}
    var explanation:String{[
        "在任何输入框里，把说的话变成文字。\n识别、整理和翻译，都在你的 Mac 上完成。",
        "麦克风用来录音，辅助功能用来填入文字。\n授权后回到这里，状态会自动刷新。",
        "识别是基础，整理和翻译可以单独选装。\n下载一次，之后不联网也能用。",
        "默认按一下右侧 Option 开始，再按一下结束。\n也可以录制你习惯的组合键。",
        "选好麦克风，读一句中英混合的话。\n看看结果，再开始日常使用。",
        "咸鱼说会留在菜单栏，等你需要时出现。\n词表和历史保存在本机，更新应用也会保留。"
    ][rawValue]}
}
struct SetupProgress:Codable {
    var version=1
    var step:SetupStep = .welcome
    var finished=false
    var deferred=false
}
@MainActor final class FirstRunState:ObservableObject {
    @Published private(set) var progress:SetupProgress
    @Published private(set) var visible=false
    @Published var error=""
    @Published var shortcutRecording=false
    @Published private(set) var trialID:UUID?
    let root:URL
    let legacy:Bool
    private var mayWrite=true
    var step:SetupStep{progress.step}
    var shouldPresentAutomatically:Bool{!legacy && !progress.finished && !progress.deferred}
    init(root:URL=AppPaths.root){
        self.root=root
        // Construct before LibraryStore, which creates an empty sessions file.
        legacy=FileManager.default.fileExists(atPath:root.appendingPathComponent("preferences.json").path) && !FileManager.default.fileExists(atPath:root.appendingPathComponent("onboarding.json").path)
        do{
            let path=root.appendingPathComponent("onboarding.json")
            progress=FileManager.default.fileExists(atPath:path.path) ? try JSONDecoder().decode(SetupProgress.self,from:Data(contentsOf:path)):SetupProgress()
        }catch{progress=SetupProgress();progress.deferred=true;mayWrite=false;self.error="引导进度读取失败，原文件已保留。可以先进入应用。"}
    }
    func present(replay:Bool=false){
        guard !visible else{return}
        if replay{progress.step = .welcome;trialID=nil}
        visible=true;if mayWrite{error=""};save()
    }
    func go(_ step:SetupStep){guard !shortcutRecording else{return};progress.step=step;if mayWrite{error=""};save()}
    func previous(){if let previous=SetupStep(rawValue:step.rawValue-1){go(previous)}}
    func deferSetup(){visible=false;progress.deferred=true;save()}
    func finish(){visible=false;progress.finished=true;progress.deferred=false;save()}
    func startedTrial(_ id:UUID){trialID=id}
    private func save(){
        guard mayWrite else{return}
        do{try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try AppPaths.write(progress,to:root.appendingPathComponent("onboarding.json"))}
        catch{self.error="引导进度未能保存："+error.localizedDescription}
    }
    static func canContinue(_ step:SetupStep,microphone:Bool,accessibility:Bool,models:Bool,shortcuts:Bool,busy:Bool)->Bool{
        guard !busy else{return false}
        switch step{case .permissions:return microphone && accessibility;case .models:return models;case .shortcuts:return shortcuts;default:return true}
    }
    static func firstMissing(microphone:Bool,accessibility:Bool,models:Bool,shortcuts:Bool)->SetupStep?{
        if !microphone || !accessibility{return .permissions};if !models{return .models};if !shortcuts{return .shortcuts};return nil
    }
}

enum SetupRegion:Hashable{case introduction,viewport,content,footer}
struct SetupFrames:PreferenceKey {
    static var defaultValue:[SetupRegion:CGRect]=[:]
    static func reduce(value:inout[SetupRegion:CGRect],nextValue:()->[SetupRegion:CGRect]){value.merge(nextValue(),uniquingKeysWith:{$1})}
}
private extension View {
    func setupRegion(_ region:SetupRegion)->some View{background(GeometryReader{proxy in Color.clear.preference(key:SetupFrames.self,value:[region:proxy.frame(in:.named("DianyuSetup"))])})}
}
struct SetupView:View {
    @ObservedObject var app:AppState
    @ObservedObject var state:FirstRunState
    @ObservedObject private var downloads=ModelDownloads.shared
    let leave:()->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DianyuDesign.appearanceKey) private var appearance="system"
    @UIState private var trialText=""
    private let accent=DianyuDesign.adaptive("SetupAccent",dark:0xFF666E,light:0xBE3541)
    private var missing:[String]{ModelCatalog.missing(cleanup:app.store.preferences.cleanup,translate:false)}
    private var shortcutReady:Bool{!state.shortcutRecording && app.shortcutError.isEmpty && !app.store.preferences.dictation.matches(app.store.preferences.translation)}
    private var canContinue:Bool{FirstRunState.canContinue(state.step,microphone:Recorder.authorized,accessibility:AXIsProcessTrusted(),models:missing.isEmpty,shortcuts:shortcutReady,busy:app.busy || state.shortcutRecording)}
    private var trial:SessionRecord?{app.store.sessions.first{$0.id==state.trialID}}
    var body:some View{
        GeometryReader{geometry in
            VStack(spacing:0){
                HStack(spacing:36){
                    introduction.frame(width:max(280,geometry.size.width*0.33),alignment:.leading)
                    GeometryReader{viewport in
                        ScrollView{
                            content.frame(maxWidth:.infinity).fixedSize(horizontal:false,vertical:true).setupRegion(.content)
                                .frame(minHeight:max(0,viewport.size.height-16),alignment:.center).padding(.vertical,8)
                        }.scrollIndicators(.hidden)
                    }.setupRegion(.viewport).id(state.step)
                }.padding(.horizontal,40).padding(.top,48).padding(.bottom,20)
                footer.setupRegion(.footer).padding(.horizontal,20).padding(.bottom,18)
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }.coordinateSpace(name:"DianyuSetup").frame(minWidth:900,minHeight:600)
        .background(DianyuDesign.adaptive("SetupBackground",dark:0x0B0C0D,light:0xF5F5F4))
        .foregroundStyle(DianyuDesign.primary).tint(accent).buttonStyle(FlatButtonStyle())
        .preferredColorScheme(appearance=="dark" ? .dark:appearance=="light" ? .light:nil)
        .animation(reduceMotion ? nil:.easeInOut(duration:0.18),value:state.step)
        .onAppear{KeyboardFocusFeedback.shared.start();app.refreshPermissions()}
        .onReceive(Timer.publish(every:1,on:.main,in:.common).autoconnect()){_ in if state.visible && state.step == .permissions{app.refreshPermissions()}}
        .onChange(of:app.phase){_,phase in if phase=="result",let trial,trial.status=="completed"{trialText=trial.output}}
        .onChange(of:state.trialID){_,_ in trialText=""}
        .onChange(of:app.store.preferences){_,_ in app.applyPreferences()}
        .onChange(of:state.step){_,step in if step == .practice{trialText=trial?.output ?? ""}}
    }
    private var introduction:some View{
        VStack(alignment:.leading,spacing:16){
            HStack(spacing:10){BrandMark(size:24);Text("咸鱼说").font(.system(size:14,weight:.semibold));Text("for Mac").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}.padding(.bottom,12)
            Text(state.step.label).font(.system(size:12,weight:.medium)).foregroundStyle(accent).padding(.horizontal,10).padding(.vertical,6).background(accent.opacity(0.10),in:Capsule())
            Text(state.step.headline).font(.system(size:32,weight:.semibold)).tracking(-0.7).lineSpacing(2).fixedSize(horizontal:false,vertical:true)
            Text(state.step.explanation).font(.system(size:13)).foregroundStyle(DianyuDesign.secondary).lineSpacing(5).fixedSize(horizontal:false,vertical:true)
        }.setupRegion(.introduction).frame(maxHeight:.infinity,alignment:.center)
    }
    @ViewBuilder private var content:some View{
        switch state.step{
        case .welcome:welcome
        case .permissions:permissions
        case .models:models
        case .shortcuts:ShortcutSettingsPage(app:app,onCapture:{state.shortcutRecording=$0})
        case .practice:practice
        case .ready:ready
        }
    }
    private func card<C:View>(@ViewBuilder _ body:()->C)->some View{
        body().padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Color.primary.opacity(0.08)))
    }
    private func badge(_ symbol:String,color:Color)->some View{
        Image(systemName:symbol).font(.system(size:20,weight:.medium)).foregroundStyle(.white).frame(width:42,height:42)
            .background(LinearGradient(colors:[color,color.opacity(0.72)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:11))
            .overlay(RoundedRectangle(cornerRadius:11).strokeBorder(.white.opacity(0.20)))
    }
    private var welcome:some View{
        VStack(spacing:16){
            card{VStack(alignment:.leading,spacing:18){
                HStack(spacing:12){badge("waveform",color:.blue);Text("说得自然，写得清楚。").font(.system(size:17,weight:.semibold))}
                Text("嗯，帮我检查一下 design.md，\n检查一下，没了。").font(.system(size:17)).foregroundStyle(DianyuDesign.secondary).lineSpacing(5)
                Divider().opacity(0.45)
                Text("帮我检查一下 design.md。").font(.system(size:20,weight:.medium))
                Text("轻整理示例 · 去赘词和重复，保留原意。").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
            }}
            HStack(spacing:14){
                card{VStack(alignment:.leading,spacing:10){badge("lock.shield",color:.purple);Text("留在本机").font(.system(size:15,weight:.semibold));Text("无需账号，录音和文字不上传。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}}
                card{VStack(alignment:.leading,spacing:10){badge("arrow.down.circle",color:.orange);Text("免费使用").font(.system(size:15,weight:.semibold));Text("模型按需下载，不用就不装。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}}
            }
        }
    }
    private func permissionRow(_ title:String,detail:String,symbol:String,color:Color,granted:Bool,action:@escaping()->Void)->some View{
        HStack(spacing:14){badge(symbol,color:color);VStack(alignment:.leading,spacing:6){Text(title).font(.system(size:16,weight:.medium));Text(detail).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)};Spacer(minLength:10)
            if granted{Label("已授权",systemImage:"checkmark.circle.fill").font(.system(size:12)).foregroundStyle(.green).frame(width:84,height:32)}
            else{Button("去授权",action:action).accessibilityLabel("授权"+title).frame(width:84)}
        }.frame(minHeight:78)
    }
    private var permissions:some View{
        VStack(alignment:.leading,spacing:18){
            permissionRow("麦克风",detail:"录制你主动开始的听写。",symbol:"mic",color:.purple,granted:Recorder.authorized){
                if AVCaptureDevice.authorizationStatus(for:.audio) == .notDetermined{Task{_ = await Recorder.request();app.refreshPermissions()}}else{app.openPrivacy("Privacy_Microphone")}
            }
            Divider().opacity(0.35)
            permissionRow("辅助功能",detail:"将结果填入输入框，支持全局快捷键。",symbol:"accessibility",color:.blue,granted:AXIsProcessTrusted()){app.requestAccessibility()}
            Divider().opacity(0.35)
            Label("无需屏幕录制、系统音频或日历权限。\n系统开关开启后，仍以这里的实际授权状态为准。",systemImage:"lock.shield").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).lineSpacing(4)
        }
    }
    private var models:some View{
        VStack(alignment:.leading,spacing:16){
            HStack{Text("模型下载源").font(.system(size:12));Spacer();FlatMenuPicker(label:"引导模型下载源",selection:$downloads.mirror,options:[("魔搭 ModelScope",true),("Hugging Face",false)]).frame(width:158).disabled(downloads.downloading)}
            card{VStack(spacing:0){ForEach(Array(downloads.specs.enumerated()),id:\.element.id){index,spec in
                if index>0{Divider().opacity(0.4).padding(.vertical,13)}
                HStack(spacing:12){badge(spec.role=="asr" ? "waveform":spec.role=="cleanup" ? "sparkles":"translate",color:spec.role=="asr" ? .blue:spec.role=="cleanup" ? .purple:.orange)
                    VStack(alignment:.leading,spacing:5){Text(spec.title+(spec.role=="asr" ? " · 必需":" · 选装")).font(.system(size:14,weight:.semibold));Text(spec.id).font(.system(size:10)).foregroundStyle(DianyuDesign.secondary)
                        Text(modelSize(spec)).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}
                    Spacer(minLength:8)
                    if ModelCatalog.installed(spec.id){Image(systemName:"checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(spec.title+"已安装")}
                    else if downloads.activeID==spec.id{Button("暂停"){downloads.pause()}.accessibilityLabel("暂停"+spec.title+"下载")}
                    else{Button("下载"){downloads.start(spec)}.disabled(downloads.downloading || app.resourcesBusy).accessibilityLabel("下载"+spec.title)}
                }
            }}}
            if downloads.downloading{ProgressView(value:downloads.fraction);Text(downloads.status+" \(Int(downloads.fraction*100))%").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}
            else{Text(downloads.status).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}
            VStack(alignment:.leading,spacing:9){Text("默认整理程度").font(.system(size:12,weight:.medium));FlatSegmented(label:"引导整理程度",selection:$app.store.preferences.cleanup,options:CleanupMode.allCases.map{($0.title,$0)});Text(app.store.preferences.cleanup.detail+"\n只装识别模型时，请选“不整理”；翻译模型始终选装。").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}.disabled(app.busy)
        }
    }
    private func modelSize(_ spec:ModelSpec)->String{let files=(try? ModelResources.manifest()[spec.id]) ?? [];return String(format:"%.2f GB",Double(files.reduce(Int64(0)){$0+$1.bytes})/1_000_000_000)}
    private var chosenMicrophone:String{AudioDevices.resolve(uid:app.store.preferences.microphoneUID,preferBuiltIn:app.store.preferences.preferBuiltIn,choices:app.microphones,defaultDevice:AudioDevices.defaultInput())?.name ?? "设备不可用，请重新选择"}
    private var practice:some View{
        VStack(alignment:.leading,spacing:16){
            card{VStack(alignment:.leading,spacing:14){
                HStack{Text("输入设备").font(.system(size:12));Spacer();FlatMenuPicker(label:"引导麦克风",selection:$app.store.preferences.microphoneUID,options:[("跟随系统默认","")]+app.microphones.map{($0.name,$0.id)}).frame(width:190).disabled(app.busy)}
                Text("当前选择："+chosenMicrophone+"\n"+(trial == nil ? "开始试说后会显示实际录音设备。":app.microphoneRoute)).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
                Divider().opacity(0.4)
                Text("请检查 design.md，这个单词是 thief，不是 theft。").font(.system(size:17,weight:.medium)).lineSpacing(5)
                Text(app.store.preferences.holdToTalk ? "按住 \(app.store.preferences.dictation.label) 说话，松开结束；也可以点击下方按钮。":"按 \(app.store.preferences.dictation.label) 开始，再按一次结束；也可以点击下方按钮。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:12){
                    Button(app.capturing ? "结束试说":app.busy ? "正在处理…":"试说一句"){if app.capturing{app.finish()}else{app.begin(practice:true)}}.disabled(app.busy && !app.capturing).buttonStyle(FlatButtonStyle(kind:.primary))
                    if app.busy{Button("取消"){app.cancel()}}
                    Text(app.busy ? app.stage:trial?.status=="completed" ? "试说已完成":"结果会显示在下方").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)
                }
            }}
            VStack(alignment:.leading,spacing:8){
                HStack{Text("你的试说结果").font(.system(size:12,weight:.medium));Spacer();if !trialText.isEmpty{Button("复制结果"){Delivery.copy(trialText)}}}
                ZStack(alignment:.topLeading){
                    TextEditor(text:$trialText).font(.system(size:14)).scrollContentBackground(.hidden).padding(8).accessibilityLabel("引导试说结果")
                    if trialText.isEmpty{Text("说完后，文字会出现在这里。").font(.system(size:13)).foregroundStyle(DianyuDesign.tertiary).padding(13).allowsHitTesting(false)}
                }.frame(height:100).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Color.primary.opacity(0.08)))
                Text(trial?.status=="failed" ? trial?.error ?? "试说未完成，可重试。":"试说保留在历史，不计入输入统计。个人词表会完整参与本次识别。").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }.onAppear{app.refreshDevices()}
    }
    private var ready:some View{
        VStack(spacing:22){
            BrandMark(size:76)
            KeycapStrip(keys:app.store.preferences.dictation.keycaps).frame(height:88)
            Text("\(app.store.preferences.dictation.label) · 开始 / 结束听写").font(.system(size:15,weight:.medium))
            card{VStack(alignment:.leading,spacing:14){
                summary("麦克风与辅助功能",ready:Recorder.authorized && AXIsProcessTrusted())
                summary("听写所需模型",ready:missing.isEmpty)
                summary("全局快捷键",ready:shortcutReady)
                Divider().opacity(0.4)
                Text("\(app.store.activeWords.count) 个启用词条 · \(app.store.preferences.cleanup.title)\n没有光标时，结果会保留在历史；可粘贴时也会有提示。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).lineSpacing(5)
            }}
            Text("关闭窗口后仍可在菜单栏找到咸鱼说。\n菜单里的“退出咸鱼说”才会结束程序。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth:.infinity)
    }
    private func summary(_ label:String,ready:Bool)->some View{HStack{Text(label).font(.system(size:12));Spacer();Label(ready ? "已就绪":"稍后设置",systemImage:ready ? "checkmark.circle.fill":"circle.dashed").font(.system(size:11)).foregroundStyle(ready ? Color.green:DianyuDesign.secondary)}}
    private var footer:some View{
        HStack(spacing:16){
            Button{state.previous()}label:{Image(systemName:"chevron.left").font(.system(size:14,weight:.medium)).frame(width:36,height:36).background(Color.primary.opacity(0.07),in:Circle())}.buttonStyle(.plain).disabled(state.step == .welcome || app.busy || state.shortcutRecording).accessibilityLabel("引导上一步")
            HStack(spacing:5){ForEach(SetupStep.allCases,id:\.rawValue){step in Capsule().fill(step==state.step ? accent:Color.primary.opacity(0.14)).frame(width:step==state.step ? 36:13,height:3)}}.accessibilityLabel("第 \(state.step.rawValue+1) 步，共 6 步")
            Spacer(minLength:10)
            Text(state.error).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).lineLimit(2).frame(maxWidth:210)
            Button("稍后设置"){state.deferSetup();leave()}.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).disabled(app.busy || state.shortcutRecording).accessibilityLabel("稍后设置，进入应用")
            if [.permissions,.models,.shortcuts].contains(state.step),!canContinue{Button("跳过此步"){advance(skip:true)}.buttonStyle(.plain).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).disabled(app.busy || state.shortcutRecording)}
            Button{advance()}label:{HStack(spacing:10){Text(primaryTitle).font(.system(size:13,weight:.semibold));Image(systemName:"return").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}.padding(.horizontal,18).frame(height:36).background(Color.primary.opacity(0.10),in:Capsule()).overlay(Capsule().strokeBorder(Color.primary.opacity(0.09)))}.buttonStyle(.plain).disabled(!canContinue).keyboardShortcut(.return,modifiers:[])
        }.frame(height:40)
    }
    private var primaryTitle:String{state.step == .welcome ? "开始设置":state.step == .ready ? "开始使用咸鱼说":state.step == .practice && trialText.isEmpty ? "跳过试说":"继续"}
    private func advance(skip:Bool=false){
        guard !app.busy,!state.shortcutRecording,skip || canContinue else{return}
        if state.step == .ready{
            if let missing=FirstRunState.firstMissing(microphone:Recorder.authorized,accessibility:AXIsProcessTrusted(),models:missing.isEmpty,shortcuts:shortcutReady){state.go(missing);state.error="还有一项未就绪，也可点“稍后设置”先进入应用。";return}
            state.finish();leave()
        }else if let next=SetupStep(rawValue:state.step.rawValue+1){state.go(next)}
    }
}

@MainActor final class SetupWindowController:NSObject,NSWindowDelegate {
    let window:NSWindow
    private let app:AppState
    private let leave:()->Void
    init(app:AppState,leave:@escaping()->Void){
        self.app=app;self.leave=leave
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:980,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init()
        window.identifier=NSUserInterfaceItemIdentifier("onboarding");window.title="欢迎使用咸鱼说";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true
        window.isReleasedWhenClosed=false;window.minSize=NSSize(width:900,height:600);window.delegate=self;window.isMovableByWindowBackground=true
        let host=ClearHostingView(rootView:SetupView(app:app,state:app.onboarding,leave:{[weak self]in self?.dismiss()}));host.sizingOptions=[];window.contentView=host
        window.center()
    }
    func show(){window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    func dismiss(){guard !app.busy,!app.onboarding.shortcutRecording else{return};window.orderOut(nil);app.pauseShortcutCapture(false);leave()}
    nonisolated func windowShouldClose(_ sender:NSWindow)->Bool{MainActor.assumeIsolated{
        guard !app.busy,!app.onboarding.shortcutRecording else{app.onboarding.error="请先结束或取消当前操作。";return false}
        app.onboarding.deferSetup();app.pauseShortcutCapture(false);DefaultModeAction.enqueue{[weak self]in self?.leave()};return true
    }}
}
