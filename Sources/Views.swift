import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import UniformTypeIdentifiers
import Combine

private struct NavigationEntry:Identifiable{let id:String,title:String,symbol:String,color:Color}
private struct NavigationHover:ButtonStyle {
    @UIState private var hover=false
    @Environment(\.isFocused) private var focused
    @ObservedObject private var focusFeedback=KeyboardFocusFeedback.shared
    func makeBody(configuration:Configuration)->some View{configuration.label.contentShape(Rectangle()).background(Color.primary.opacity(configuration.isPressed ? 0.11:hover ? 0.05:0),in:RoundedRectangle(cornerRadius:10)).overlay{if focused && focusFeedback.visible{RoundedRectangle(cornerRadius:10).strokeBorder(DianyuDesign.focus,lineWidth:2).allowsHitTesting(false)}}.onHover{hover=$0}}
}
struct RootView:View {
    let app:AppState
    @ObservedObject private var navigation:PageSelection
    @AppStorage(DianyuDesign.appearanceKey) private var appearance="system"
    @UIState private var capturePhase:String?
    @UIState private var storageError=""
    init(app:AppState){self.app=app;navigation=app.navigation}
    private var page:String{navigation.value}
    private var settingsSection:String?{SettingsWorkspace.sections.contains(page) ? page:nil}
    private var title:String{page=="设置" ? "通用":page=="模型资源" ? "模型":page}
    private var subtitle:String{
        switch page{case "设置":return "外观、输出与本地记录。";case "录音":return "选择麦克风，让每次起录更从容。";case "快捷键":return "按你的习惯，随时开始听写与翻译。";case "权限":return "管理录音与跨应用填入所需的系统授权。";case "关于":return "版本、更新与本地隐私。";case "模型资源":return "识别、整理与翻译，全部在这台 Mac 上完成。";case "统计":return "看看你用声音写下了多少内容。";case "历史":return "原音、原文与每一次结果，都可以找回。";case "个人词表":return "让常用词参与每一次识别。";default:return "在本机识别、整理，再写入当前应用。"}
    }
    var body:some View{
        HStack(spacing:0){
            NavigationGlass(content:NavigationSidebar(app:app)).equatable().frame(width:DianyuDesign.sidebarWidth)
                .padding(.leading,DianyuDesign.sidebarInset).padding(.trailing,12).padding(.vertical,DianyuDesign.sidebarInset)
            VStack(alignment:.leading,spacing:0){
                VStack(alignment:.leading,spacing:5){Text(title).font(.system(size:28,weight:.semibold));Text(subtitle).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(.leading,20).padding(.trailing,24).padding(.top,26).padding(.bottom,page=="个人词表" ? 10:20)
                if let capturePhase,page != "输入"{
                    HStack{Label(capturePhase=="preparing" ? "麦克风准备中，关闭窗口会取消准备。":"录音继续进行，关闭窗口会结束并保存。",systemImage:"mic.fill").font(.system(size:12));Spacer();Button("返回录音"){app.page="输入"};Button(capturePhase=="preparing" ? "取消准备":"结束并保存"){if app.phase=="preparing"{app.cancel()}else{app.finish()}}}.foregroundStyle(DianyuDesign.secondary).padding(.leading,20).padding(.trailing,24).padding(.bottom,14)
                }
                if !storageError.isEmpty{Text(storageError).foregroundStyle(.orange).padding(.leading,20).padding(.trailing,24).padding(.bottom,12)}
                ZStack(alignment:.topLeading){
                    SettingsWorkspace(app:app,section:settingsSection)
                    if settingsSection==nil{
                        switch page{
                        case "历史":HistoryPage(app:app)
                        case "个人词表":VocabularyPage(app:app)
                        case "统计":StatisticsPage(store:app.store)
                        default:InputPage(app:app)
                        }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(DianyuDesign.page)
        }.background(DianyuDesign.page).frame(minWidth:920,minHeight:640).ignoresSafeArea().tint(DianyuDesign.accent)
            .foregroundStyle(DianyuDesign.primary).buttonStyle(FlatButtonStyle()).preferredColorScheme(appearance=="dark" ? .dark:appearance=="light" ? .light:nil)
            .onReceive(app.$phase.map{["preparing","recording"].contains($0) ? $0:nil}.removeDuplicates()){capturePhase=$0}
            .onReceive(app.store.$storageError.removeDuplicates()){storageError=$0}
            .onAppear{DianyuDesign.applyAppearance();KeyboardFocusFeedback.shared.start()}.onChange(of:appearance){_ in DianyuDesign.applyAppearance()}
    }
}
/// Retained inside its own AppKit host. Only navigation and the footer status
/// subscribe here; recording ticks and unrelated settings never replace its root.
private struct NavigationSidebar:View,Equatable {
    let app:AppState
    @UIState private var query=""
    @UIState private var page=""
    @UIState private var busy=false
    @UIState private var failed=false
    static func ==(lhs:Self,rhs:Self)->Bool{lhs.app === rhs.app}
    private let workspace:[NavigationEntry]=[
        .init(id:"输入",title:"输入",symbol:"waveform",color:.blue),.init(id:"历史",title:"历史",symbol:"clock.arrow.circlepath",color:.orange),.init(id:"个人词表",title:"个人词表",symbol:"text.book.closed",color:.purple),.init(id:"统计",title:"统计",symbol:"chart.bar.xaxis",color:.green)]
    private let preferences:[NavigationEntry]=[
        .init(id:"设置",title:"通用",symbol:"slider.horizontal.3",color:.gray),.init(id:"录音",title:"录音",symbol:"mic",color:.purple),.init(id:"快捷键",title:"快捷键",symbol:"command",color:.pink),.init(id:"权限",title:"权限",symbol:"lock.shield",color:.cyan),.init(id:"模型资源",title:"模型",symbol:"cpu",color:.orange),.init(id:"关于",title:"关于",symbol:"info.circle",color:.blue)]
    var body:some View{
        VStack(alignment:.leading,spacing:0){
            NativeWindowControls().frame(height:30).padding(.bottom,12)
            HStack(spacing:10){BrandMark(size:36);VStack(alignment:.leading,spacing:4){Text("咸鱼说").font(.system(size:19,weight:.bold));Text("把想法，说出来。").font(.system(size:11)).foregroundStyle(DianyuDesign.onGlassMuted)};Spacer(minLength:0)}.padding(.horizontal,10).padding(.bottom,22)
            SearchField(placeholder:"搜索页面",text:$query).padding(.bottom,12)
            ViewThatFits(in:.vertical){
                navigationGroups
                ScrollView{navigationGroups}.scrollIndicators(.hidden)
            }.frame(maxHeight:.infinity,alignment:.topLeading)
            Rectangle().fill(DianyuDesign.line).frame(height:1).padding(.bottom,14)
            HStack{Text("版本 \(DianyuDesign.version)");Spacer();HStack(spacing:5){Circle().fill(failed ? Color.orange:DianyuDesign.accent.opacity(0.65)).frame(width:4,height:4);Text(busy ? "处理中":"完全本地")}}.font(.system(size:11)).foregroundStyle(DianyuDesign.onGlassMuted).padding(.horizontal,8).padding(.bottom,8)
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).ignoresSafeArea()
            .onReceive(app.navigation.$value){page=$0}
            .onReceive(app.$phase.map{$0=="error"}.removeDuplicates()){failed=$0}
            .onReceive(app.$phase.combineLatest(app.$resourcesBusy){phase,resourcesBusy in
                resourcesBusy || ["preparing","recording","working"].contains(phase)
            }.removeDuplicates()){busy=$0}
    }
    private var navigationGroups:some View{
        VStack(alignment:.leading,spacing:4){
            navigationGroup("工作区",entries:workspace)
            navigationGroup("偏好设置",entries:preferences)
            if !(workspace+preferences).contains(where:matches){Text("没有匹配的页面").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).padding(12)}
        }.padding(.bottom,12)
    }
    private func matches(_ e:NavigationEntry)->Bool{query.isEmpty || e.title.localizedCaseInsensitiveContains(query)}
    @ViewBuilder private func navigationGroup(_ title:String,entries:[NavigationEntry])->some View{
        let filtered=entries.filter(matches)
        if !filtered.isEmpty{
            Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(DianyuDesign.onGlassMuted).padding(.horizontal,10).padding(.top,title=="工作区" ? 0:20).padding(.bottom,6)
            ForEach(filtered){entry in Button{app.page=entry.id}label:{
                HStack(spacing:11){Image(systemName:entry.symbol).font(.system(size:15,weight:.medium)).foregroundStyle(page==entry.id ? .white:entry.color).frame(width:23,height:23).background(entry.color.opacity(page==entry.id ? 0.80:0.18),in:RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(entry.color.opacity(0.26),lineWidth:0.7));Text(entry.title).font(.system(size:13.5,weight:page==entry.id ? .semibold:.medium));Spacer(minLength:0)}.foregroundStyle(.primary).padding(.horizontal,10).frame(height:38).background(page==entry.id ? Color.primary.opacity(0.12):.clear,in:RoundedRectangle(cornerRadius:11)).contentShape(Rectangle()).textSelection(.disabled)
            }.buttonStyle(NavigationHover()).focusEffectDisabled().accessibilityAddTraits(page==entry.id ? [.isSelected]:[]) }
        }
    }
}
struct InputPage:View {
    @ObservedObject var app:AppState
    @AppStorage("dianyu.input.testText") private var testText=""
    var body:some View{
        ScrollView{
            VStack(alignment:.leading,spacing:22){
                VStack(alignment:.leading,spacing:20){
                    HStack{Text("语音输入").font(.system(size:12,weight:.semibold)).foregroundStyle(DianyuDesign.secondary);Spacer();HStack(spacing:6){Circle().fill(app.busy ? DianyuDesign.accent:Color.green.opacity(0.7)).frame(width:5,height:5);Text(app.busy ? app.stage:app.engineStatus).lineLimit(1);if app.phase=="recording"{recordingClock}}.font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}
                    HStack(spacing:28){
                        VStack(alignment:.leading,spacing:8){Text(app.phase=="recording" ? "正在听你说":app.phase=="preparing" ? "正在准备麦克风":app.phase=="working" ? "正在本机处理":"随时开始一段听写").font(.system(size:21,weight:.semibold));Text(app.phase=="recording" ? "再按快捷键结束，Esc 取消。":app.phase=="preparing" ? "等待麦克风准备，可随时取消。":"用自己的话，把想法自然说出来。").font(.system(size:13)).foregroundStyle(DianyuDesign.secondary)}.frame(maxWidth:.infinity,alignment:.leading)
                        DotMatrix(source:app.meter,phase:app.phase).frame(width:230,height:54)
                    }
                    HStack(spacing:10){
                        Button{if app.phase=="preparing"{app.cancel()}else if app.capturing{app.finish()}else{app.begin()}}label:{Label(app.phase=="preparing" ? "取消准备":app.capturing ? "结束录音":"开始听写",systemImage:app.capturing ? "stop.fill":"mic").frame(minWidth:94,minHeight:8)}.buttonStyle(FlatButtonStyle(kind:.primary)).disabled(app.phase=="working" || app.resourcesBusy)
                        Button{app.begin(translate:true)}label:{Label("直接出英文",systemImage:"translate").frame(minWidth:102,minHeight:8)}.disabled(app.busy)
                        if app.busy && app.phase != "preparing"{Button("取消"){app.cancel()}.keyboardShortcut(.cancelAction)}
                        Spacer(minLength:4)
                        VStack(alignment:.trailing,spacing:4){Text("听写  \(app.store.preferences.dictation.label)");Text("翻译  \(app.store.preferences.translation.label)")}.font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
                    }
                }.padding(20).background(DianyuDesign.feature,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(DianyuDesign.line,lineWidth:1))
                VStack(spacing:0){
                    PreferenceRow(title:"整理程度",detail:app.store.preferences.cleanup.detail,symbol:"sparkles"){
                        FlatSegmented(label:"整理程度",selection:$app.store.preferences.cleanup,options:CleanupMode.allCases.map{($0.title,$0)}).frame(width:290).disabled(app.busy)
                    }
                    PreferenceDivider()
                    PreferenceRow(title:"个人词表",detail:"\(app.store.activeWords.count) 个启用词条将参与下一次识别",symbol:"text.book.closed"){
                        Button{app.page="个人词表"}label:{HStack(spacing:7){Text("管理词表");Image(systemName:"chevron.right").font(.system(size:11))}}
                    }
                }.background(DianyuDesign.group,in:RoundedRectangle(cornerRadius:15))
                if !app.shortcutError.isEmpty{Label(app.shortcutError,systemImage:"exclamationmark.triangle").font(.system(size:12)).foregroundStyle(.orange)}
                if !app.notice.isEmpty{notice}
                if let record=app.latestRecord{ResultView(record:record,app:app).id(record.id)}
                DisclosureGroup("文本整理自测（不计入输入统计）"){
                    VStack(alignment:.leading,spacing:12){TextEditor(text:$testText).font(.system(size:13)).scrollContentBackground(.hidden).padding(10).frame(height:110).background(DianyuDesign.inset,in:RoundedRectangle(cornerRadius:8));HStack{Button("测试当前整理档位"){app.testText(testText,translate:false)};Button("测试中文转英文"){app.testText(testText,translate:true)}}.disabled(app.busy || testText.isEmpty)}.padding(.top,12)
                }.font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).padding(.vertical,12)
            }.padding(.leading,20).padding(.trailing,24).padding(.bottom,28)
        }.onChange(of:app.store.preferences.cleanup){_ in app.store.savePreferences()}
    }
    private var recordingClock:some View{
        TimelineView(.periodic(from:app.recordingStartedAt,by:1)){context in
            let seconds=max(0,Int(context.date.timeIntervalSince(app.recordingStartedAt)))
            Text(String(format:"%02d:%02d",seconds/60,seconds%60)).monospacedDigit()
        }
    }
    private var notice:some View{
        let needsAttention=app.phase=="error" || app.deliveryState=="unverified" || app.notice.contains("未自动填入")
        return HStack(alignment:.top,spacing:12){Image(systemName:needsAttention ? "info.circle":"checkmark.circle").padding(.top,1);Text(app.notice).font(.system(size:12)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading);if needsAttention,let r=app.latestRecord,!r.output.isEmpty{Button("复制结果"){Delivery.copy(r.output)}.buttonStyle(FlatButtonStyle(kind:.quiet))}}
            .foregroundStyle(needsAttention ? Color.orange.opacity(0.85):DianyuDesign.secondary).padding(14).background(needsAttention ? Color.orange.opacity(0.045):Color.clear,in:RoundedRectangle(cornerRadius:10))
    }
}
struct ResultView:View {
    let record:SessionRecord
    @ObservedObject var app:AppState
    var heading="最近结果"
    @AppStorage private var version:String
    init(record:SessionRecord,app:AppState,heading:String="最近结果"){
        self.record=record;self.app=app;self.heading=heading
        self._version=AppStorage(wrappedValue:"最终结果","dianyu.result.version."+heading+record.id.uuidString)
    }
    var text:String{switch version{case "原始识别":return record.raw;case "整理结果":return record.cleaned;case "英文译文":return record.translated;default:return record.output}}
    var hasAudio:Bool{!record.audioFile.isEmpty && FileManager.default.fileExists(atPath:AppPaths.audio.appendingPathComponent(record.audioFile).path)}
    var body:some View{
        VStack(alignment:.leading,spacing:16){
            HStack{Text(heading).font(.system(size:heading=="最近结果" ? 14:21,weight:.semibold));Spacer();Text(record.created,style:.time).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}
            if heading != "最近结果"{
                HStack{Label(hasAudio ? String(format:"原音 · %.1f 秒",record.duration):"没有可用原音",systemImage:"headphones").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary);Spacer();Button{AudioReplay.shared.play(AppPaths.audio.appendingPathComponent(record.audioFile))}label:{Image(systemName:"play")}.disabled(!hasAudio).accessibilityLabel("回放原音");Button{AudioReplay.shared.stop()}label:{Image(systemName:"stop")}.disabled(!hasAudio).accessibilityLabel("停止回放")}.padding(12).background(DianyuDesign.feature,in:RoundedRectangle(cornerRadius:8))
            }
            VStack(alignment:.leading,spacing:20){
                FlatSegmented(label:"结果版本",selection:$version,options:(record.translate ? ["最终结果","原始识别","整理结果","英文译文"]:["最终结果","原始识别","整理结果"]).map{($0,$0)}).frame(maxWidth:record.translate ? 390:310)
                if text.isEmpty{Text(record.error.isEmpty ? "暂无"+version+"。可回放原音，或按当前档位重新处理。":record.error).foregroundStyle(DianyuDesign.secondary).padding(.vertical,12)}else{Text(text).font(.system(size:15)).lineSpacing(7).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                Rectangle().fill(DianyuDesign.line).frame(height:1)
                HStack(spacing:8){
                    Button{Delivery.copy(text);app.notice="已复制。"}label:{Label("复制",systemImage:"doc.on.doc")}.disabled(text.isEmpty)
                    Button{app.retry(record)}label:{Label("重新处理",systemImage:"arrow.clockwise")}.disabled(app.busy).accessibilityLabel("使用当前档位重新处理")
                    Spacer(minLength:0)
                    if heading=="最近结果"{
                    Button{AudioReplay.shared.play(AppPaths.audio.appendingPathComponent(record.audioFile))}label:{Image(systemName:"play")}.disabled(!hasAudio).buttonStyle(FlatButtonStyle(kind:.quiet)).help(hasAudio ? "回放原音":"原音不可用").accessibilityLabel("回放原音")
                    Button{AudioReplay.shared.stop()}label:{Image(systemName:"stop")}.disabled(!hasAudio).buttonStyle(FlatButtonStyle(kind:.quiet)).help("停止回放").accessibilityLabel("停止回放")
                    }
                }
                ViewThatFits(in:.horizontal){HStack{metadata;Spacer();timing};VStack(alignment:.leading,spacing:5){metadata;timing}}
            }.padding(18).background(DianyuDesign.group,in:RoundedRectangle(cornerRadius:15))
            if heading != "最近结果",!record.delivery.isEmpty{Label(record.delivery,systemImage:record.delivery.contains("未") ? "info.circle":"checkmark.circle").font(.system(size:12)).foregroundStyle(record.delivery.contains("未") ? Color.orange:DianyuDesign.secondary).textSelection(.enabled)}
            if !record.error.isEmpty{Text(record.error).font(.system(size:12)).foregroundStyle(.orange)}
            if !record.metadata.isEmpty{DisclosureGroup("词表与处理验证记录"){Text(record.metadata).font(.system(size:11,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding(.top,10)}.font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
            if !record.versions.isEmpty{DisclosureGroup("之前的结果版本（\(record.versions.count)）"){ForEach(Array(record.versions.enumerated()),id:\.offset){_,text in Text(text).textSelection(.enabled).padding(.vertical,8)}}.font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
        }
    }
    private var metadata:some View{Text("\(record.cleanup.title) · 词表快照 \(record.words.count) 项 · \(record.source=="microphone" ? "麦克风录音":record.source=="onboarding" ? "引导试说":"自测 / 导入")").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}
    private var timing:some View{Text(record.processingSeconds>0 ? String(format:"处理 %.2f 秒",record.processingSeconds):"等待处理").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}
}
struct HistoryPage:View {
    @ObservedObject var app:AppState
    @AppStorage("dianyu.history.query") private var query=""
    @AppStorage("dianyu.history.selected") private var selectionID=""
    @AppStorage("dianyu.history.scroll") private var scrollID=""
    @FocusState private var focusedRecord:UUID?
    @ObservedObject private var focusFeedback=KeyboardFocusFeedback.shared
    var selected:UUID?{get{UUID(uuidString:selectionID)}nonmutating set{selectionID=newValue?.uuidString ?? ""}}
    var filtered:[SessionRecord]{app.store.sessions.filter{query.isEmpty || ($0.raw+$0.output+$0.error).localizedCaseInsensitiveContains(query)}.sorted{$0.created>$1.created}}
    var scrollPosition:Binding<UUID?>{Binding(get:{UUID(uuidString:scrollID)},set:{scrollID=$0?.uuidString ?? ""})}
    var body:some View{
        let filtered=filtered
        let calendar=Calendar.current
        let byDay=Dictionary(grouping:filtered){calendar.startOfDay(for:$0.created)}
        GeometryReader{layout in
            HStack(spacing:0){
                VStack(alignment:.leading,spacing:14){
                    SearchField(placeholder:"搜索原文和结果",text:$query)
                    Text("\(filtered.count) 条记录").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
                    if filtered.isEmpty{FlatEmptyState(title:query.isEmpty ? "还没有输入记录":"没有匹配记录",detail:query.isEmpty ? "开始听写后，记录会保存在这里。":"换个词试试，或清除搜索。",symbol:"magnifyingglass")}else{
                        ScrollViewReader{proxy in
                            ScrollView{
                                LazyVStack(alignment:.leading,spacing:6){
                                    ForEach(byDay.keys.sorted(by:>),id:\.self){day in
                                        Text(dayTitle(day)).font(.system(size:11,weight:.medium)).foregroundStyle(DianyuDesign.tertiary).padding(.horizontal,10).padding(.top,12)
                                        ForEach(byDay[day] ?? []){r in
                                            Button{selected=r.id}label:{
                                                VStack(alignment:.leading,spacing:8){
                                                    Text(r.output.isEmpty ? r.raw.isEmpty ? "待恢复的录音":r.raw:r.output).font(.system(size:12.5,weight:.medium)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                                    HStack{Text(r.created,style:.time);Text(r.cleanup.title);Spacer(minLength:0);Circle().fill(["已完成","已填入"].contains(historyStatus(r)) ? Color.green.opacity(0.7):Color.orange).frame(width:4,height:4);Text(historyStatus(r))}.font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
                                                }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(selected==r.id ? DianyuDesign.selection.opacity(0.7):.clear,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle()).textSelection(.disabled)
                                            }.buttonStyle(.plain).id(r.id).focusable().focusEffectDisabled().focused($focusedRecord,equals:r.id).accessibilityAddTraits(selected==r.id ? [.isSelected]:[])
                                                .overlay{if focusedRecord==r.id && focusFeedback.visible{RoundedRectangle(cornerRadius:8).strokeBorder(DianyuDesign.focus,lineWidth:2).allowsHitTesting(false)}}
                                                .onMoveCommand{direction in if direction == .up || direction == .down{move(from:r.id,offset:direction == .up ? -1:1,proxy:proxy)}}
                                                .onKeyPress(.home){if let first=filtered.first{select(first.id,proxy:proxy)};return .handled}
                                                .onKeyPress(.end){if let last=filtered.last{select(last.id,proxy:proxy)};return .handled}
                                        }
                                    }
                                }.scrollTargetLayout()
                            }.scrollIndicators(.hidden).scrollPosition(id:scrollPosition)
                        }
                    }
                    Button{app.importAudio()}label:{Label("导入一条音频",systemImage:"square.and.arrow.down")}.disabled(app.busy)
                }.padding(.leading,20).padding(.trailing,16).padding(.bottom,24).frame(width:layout.size.width<900 ? 265:310)
                Rectangle().fill(DianyuDesign.line).frame(width:1)
                ScrollView{
                    if let r=app.store.sessions.first(where:{$0.id==selected}){ResultView(record:r,app:app,heading:"输入记录").id(r.id).padding(24)}
                    else{FlatEmptyState(title:"所有输入都可以找回",detail:"选择一条历史，查看原音、原始识别和最终结果。",symbol:"clock.arrow.circlepath").frame(minHeight:400)}
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.onChange(of:query){_ in if !filtered.contains(where:{$0.id==selected}){selected=nil}}
    }
    func select(_ id:UUID,proxy:ScrollViewProxy){selected=id;focusedRecord=id;proxy.scrollTo(id)}
    func move(from id:UUID,offset:Int,proxy:ScrollViewProxy){guard let index=filtered.firstIndex(where:{$0.id==id}),!filtered.isEmpty else{return};select(filtered[max(0,min(filtered.count-1,index+offset))].id,proxy:proxy)}
    func historyStatus(_ record:SessionRecord)->String{
        if ["recording","processing"].contains(record.status){return "处理中"}
        if record.status=="cancelled"{return "已取消"}
        if record.status=="failed"{return "失败"}
        guard record.status=="completed",!record.output.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return "可恢复"}
        if record.delivery.contains("未能确认"){return "待确认"}
        if record.delivery.contains("未自动填入"){return record.delivery.contains("复制") ? "可粘贴":"可恢复"}
        if record.delivery.contains("已填入"){return "已填入"}
        return "已完成"
    }
    func dayTitle(_ date:Date)->String{Calendar.current.isDateInToday(date) ? "今天":Calendar.current.isDateInYesterday(date) ? "昨天":date.formatted(date:.abbreviated,time:.omitted)}
}
struct VocabularyPage:View {
    @ObservedObject var app:AppState
    @AppStorage("dianyu.vocabulary.draft") private var word=""
    @UIState private var editing:VocabularyEntry?
    @UIState private var editWord=""
    @UIState private var editError=""
    @UIState private var focusSearch=false
    @FocusState private var focusedAction:String?
    @AppStorage("dianyu.vocabulary.query") private var query=""
    @AppStorage("dianyu.vocabulary.filter") private var filter="全部"
    @UIState private var message=""
    @UIState private var removing:VocabularyEntry?
    var filtered:[VocabularyEntry]{app.store.vocabulary.filter{(query.isEmpty || VocabularyRules.key($0.word).contains(VocabularyRules.key(query))) && (filter=="全部" || (filter=="已启用" ? $0.enabled:!$0.enabled))}}
    func save(_ values:[VocabularyEntry]){do{try app.store.saveVocabulary(values);message="已保存，下一次任务立即生效。"}catch{message=error.localizedDescription}}
    var body:some View{
        let filtered=filtered
        ScrollView{
            LazyVStack(alignment:.leading,spacing:12){
                if let suggestion=app.correctionSuggestion{
                    PreferenceCard(title:"改字建议",detail:"检测到本次填入后的手动修正，由你决定是否记住。"){
                        PreferenceRow(title:suggestion.word,detail:"加入后，从下一次录音开始提供词语提示。",symbol:"text.badge.plus"){
                            HStack{Button("忽略"){app.ignoreCorrection()};Button("加入词表"){app.acceptCorrection()}.buttonStyle(FlatButtonStyle(kind:.primary))}.disabled(app.busy)
                        }
                    }
                }
                VStack(alignment:.leading,spacing:8){
                    HStack(spacing:12){
                        Text("添加词条").font(.system(size:14,weight:.semibold)).fixedSize()
                        TextField("英文单词、产品名或常用短语",text:$word).accessibilityLabel("新增词条").textFieldStyle(.plain).onSubmit{add()}.padding(.horizontal,12).frame(height:38).background(DianyuDesign.inset,in:RoundedRectangle(cornerRadius:8))
                        Button{add()}label:{Label("添加",systemImage:"plus").frame(minWidth:64,minHeight:8)}.buttonStyle(FlatButtonStyle(kind:.primary)).disabled(word.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || app.busy)
                    }
                    Label(message.isEmpty ? "识别时提供词语提示，整理时保留正确写法，不会强制替换。":message,systemImage:"info.circle").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).textSelection(.enabled)
                }.padding(12).background(DianyuDesign.feature,in:RoundedRectangle(cornerRadius:15))
                HStack{Text("我的词条").font(.system(size:14,weight:.semibold));Text("\(app.store.vocabulary.count)").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).padding(.horizontal,7).padding(.vertical,3).background(DianyuDesign.control,in:RoundedRectangle(cornerRadius:5));Spacer();Button{importWords()}label:{Label("导入词表",systemImage:"square.and.arrow.down")};Button{exportWords()}label:{Label("导出词表",systemImage:"square.and.arrow.up")}}.disabled(app.busy)
                LazyVStack(spacing:0){
                    HStack(spacing:16){SearchField(placeholder:"搜索词条",text:$query,focusRequest:$focusSearch).frame(maxWidth:330);Text("显示\(filtered.count)项").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary);Spacer(minLength:0);FlatSegmented(label:"筛选词条",selection:$filter,options:["全部","已启用","已停用"].map{($0,$0)}).frame(width:234)}.padding(.horizontal,16).padding(.vertical,10)
                    HStack{Text("词条");Spacer();Text("参与识别").frame(width:66);Text("操作").frame(width:74)}.font(.system(size:11)).foregroundStyle(DianyuDesign.tertiary).padding(.horizontal,18).padding(.bottom,12)
                    Rectangle().fill(DianyuDesign.line).frame(height:1)
                    if filtered.isEmpty{FlatEmptyState(title:app.store.vocabulary.isEmpty ? "还没有个人词条":"没有匹配的词条",detail:app.store.vocabulary.isEmpty ? "可以添加常用单词、产品名或短语。":"试试其他关键词或筛选条件。",symbol:"text.magnifyingglass").frame(height:190)}else{
                        ForEach(filtered){entry in wordRow(entry);if entry.id != filtered.last?.id{Rectangle().fill(DianyuDesign.line).frame(height:1).padding(.horizontal,18)}}
                    }
                }.background(DianyuDesign.group,in:RoundedRectangle(cornerRadius:15))
                HStack{Text("\(app.store.activeWords.count) 个词条已启用");Spacer();Text("\(app.store.vocabulary.count) / 128 · 每个词条最多 80 个码点")}.font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
            }.padding(.leading,20).padding(.trailing,24).padding(.bottom,16)
        }.alert("移除词条？",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),presenting:removing){entry in
            Button("取消",role:.cancel){restoreActionFocus("remove."+entry.id.uuidString);removing=nil}.keyboardShortcut(.defaultAction)
            Button("移除",role:.destructive){removeEntry(entry)}
        }message:{entry in Text("移除“\(entry.word)”后，下一次识别将不再使用这条词语提示。")}
    }
    private func wordRow(_ entry:VocabularyEntry)->some View{
        HStack(spacing:12){Circle().fill(DianyuDesign.tertiary).frame(width:4,height:4);VocabularyWordLabel(word:entry.word).help(entry.word);Spacer(minLength:12)
            Toggle("参与识别",isOn:Binding(get:{entry.enabled},set:{enabled in var values=app.store.vocabulary;if let i=values.firstIndex(where:{$0.id==entry.id}){values[i].enabled=enabled};save(values)})).labelsHidden().toggleStyle(SwitchToggleStyle(tint:DianyuDesign.accent)).controlSize(.small).frame(width:66).accessibilityLabel("启用词条 \(entry.word)")
            HStack(spacing:3){
                Button{editing=entry;editWord=entry.word;editError=""}label:{Image(systemName:"pencil")}.buttonStyle(FlatButtonStyle(kind:.quiet)).accessibilityLabel("编辑词条 \(entry.word)").focusable().focusEffectDisabled().focused($focusedAction,equals:"edit."+entry.id.uuidString)
                    .popover(isPresented:Binding(get:{editing?.id==entry.id},set:{if !$0{closeEditor()}}),arrowEdge:.trailing){
                        VStack(alignment:.leading,spacing:16){Text("编辑词条").font(.system(size:16,weight:.semibold));TextField("词条",text:$editWord).textFieldStyle(.roundedBorder).accessibilityLabel("编辑词条").accessibilityHint(editError).onSubmit{commitEdit()};if !editError.isEmpty{Text(editError).font(.system(size:12)).foregroundStyle(.orange)};Text("最多80个码点，保存后从下一次任务生效。").font(.system(size:11)).foregroundStyle(.secondary);HStack{Button("取消"){closeEditor()};Spacer();Button("保存"){commitEdit()}.buttonStyle(FlatButtonStyle(kind:.primary)).disabled(editWord.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}.padding(20).frame(width:300)
                    }
                Button{removing=entry}label:{Image(systemName:"trash")}.buttonStyle(FlatButtonStyle(kind:.quiet)).foregroundStyle(DianyuDesign.secondary).accessibilityLabel("移除词条 \(entry.word)").focusable().focusEffectDisabled().focused($focusedAction,equals:"remove."+entry.id.uuidString)
            }.frame(width:74)
        }.frame(minHeight:41).padding(.horizontal,18).disabled(app.busy).accessibilityElement(children:.contain)
    }
    func add(){guard !app.busy else{return};let value=word.trimmingCharacters(in:.whitespacesAndNewlines);guard !value.isEmpty else{return};var next=app.store.vocabulary;next.append(VocabularyEntry(word:value));do{try app.store.saveVocabulary(next);word="";message="已保存，下一次任务立即生效。"}catch{message=error.localizedDescription}}
    func commitEdit(){guard let editing else{return};var next=app.store.vocabulary;if let i=next.firstIndex(where:{$0.id==editing.id}){next[i].word=editWord.trimmingCharacters(in:.whitespacesAndNewlines)};do{try app.store.saveVocabulary(next);closeEditor();message="词条已更新，下一次任务立即生效。"}catch{editError=error.localizedDescription}}
    func restoreActionFocus(_ key:String){focusedAction=nil;DispatchQueue.main.asyncAfter(deadline:.now()+0.18){focusedAction=key}}
    func closeEditor(){guard let entry=editing else{return};editing=nil;editError="";restoreActionFocus("edit."+entry.id.uuidString)}
    func removeEntry(_ entry:VocabularyEntry){
        let visible=filtered,index=visible.firstIndex(where:{$0.id==entry.id}) ?? 0
        let neighbors=visible.filter{$0.id != entry.id}
        do{try app.store.saveVocabulary(app.store.vocabulary.filter{$0.id != entry.id});message="词条已移除，下一次任务生效。";if !neighbors.isEmpty{restoreActionFocus("remove."+neighbors[min(index,neighbors.count-1)].id.uuidString)}else{focusedAction=nil;focusSearch=true}}catch{message=error.localizedDescription;restoreActionFocus("remove."+entry.id.uuidString)}
        removing=nil
    }
    func importWords(){
        let panel=NSOpenPanel();panel.allowedContentTypes=[.plainText,.json];guard panel.runModal() == .OK,let url=panel.url else{return}
        do{
            let size=(try FileManager.default.attributesOfItem(atPath:url.path)[.size]as?NSNumber)?.intValue ?? 0
            guard size<=VocabularyRules.maxImportBytes else{throw AppError.message("导入文件不能超过1 MiB。")}
            let batch=try VocabularyRules.imported(Data(contentsOf:url),json:url.pathExtension.lowercased()=="json",existing:app.store.vocabulary)
            try app.store.saveVocabulary(batch.values);message="已导入\(batch.added)项，跳过\(batch.skipped)项重复词条；下一次任务生效。"
        }catch{message="导入未保存："+error.localizedDescription}
    }
    func exportWords(){let panel=NSSavePanel();panel.nameFieldStringValue="咸鱼说个人词表.json";panel.allowedContentTypes=[.json];guard panel.runModal() == .OK,let url=panel.url else{return};do{try JSONEncoder().encode(app.store.vocabulary.map(\.word)).write(to:url,options:.atomic);message="词表已导出。"}catch{message=error.localizedDescription}}
}
struct StatisticsPage:View {
    @ObservedObject var store:LibraryStore
    @UIState private var today=Calendar.current.startOfDay(for:.now)
    var body:some View{
        StatisticsDashboard(records:store.sessions,now:today)
            .onReceive(NotificationCenter.default.publisher(for:.NSCalendarDayChanged)){_ in refreshDay()}
            .onReceive(NotificationCenter.default.publisher(for:.NSSystemTimeZoneDidChange)){_ in refreshDay()}
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.didWakeNotification)){_ in refreshDay()}
    }
    private func refreshDay(){today=Calendar.current.startOfDay(for:.now)}
}
struct ModelsPage:View {
    @ObservedObject var app:AppState
    @ObservedObject private var downloads=ModelDownloads.shared
    @UIState private var status=""
    var body:some View{
        ScrollView{LazyVStack(alignment:.leading,spacing:24){
            VStack(alignment:.leading,spacing:10){
                Text("用到什么，再下载什么。").font(.system(size:22,weight:.semibold))
                Text("应用安装包不包含模型。识别用于基础听写；整理和翻译可以单独选装，下载完成直接启用。").font(.system(size:13)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)
                Label(app.engineStatus,systemImage:"cpu").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)
            }
            PreferenceCard(title:"按需下载",detail:"模型文件由魔搭或 Hugging Face 下载到本机，语音内容不发送给下载平台。"){
                PreferenceRow(title:"下载源",detail:"下载中可暂停，换源后继续。",symbol:"network"){
                    FlatMenuPicker(label:"模型下载源",selection:$downloads.mirror,options:[("魔搭 ModelScope",true),("Hugging Face",false)]).frame(width:170).disabled(downloads.downloading)
                }
                ForEach(downloads.specs){spec in
                    PreferenceDivider()
                    modelRow(spec)
                }
            }
            if downloads.downloading{
                VStack(alignment:.leading,spacing:9){
                    HStack{Text(downloads.status).font(.system(size:12));Spacer();Button("暂停下载"){downloads.pause()}}
                    ProgressView(value:downloads.fraction).progressViewStyle(.linear)
                    Text("已下载 \(Int(downloads.fraction*100))% · 不影响已安装模型的使用").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
                }
            }else{Text(downloads.status).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}
            HStack{Text("只想把说的话转成文字？").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary);Spacer();Button("使用基础听写（不整理）"){app.store.preferences.cleanup = .none;app.applyPreferences();app.page="输入"}.disabled(downloads.overview["Qwen3-ASR-1.7B-8bit"]?.installed != true || app.busy)}
            PreferenceCard(title:"本地管理",detail:"现有模型保持独立，应用更新无需重新下载。"){
                PreferenceRow(title:"模型文件夹",detail:"可从其他电脑复制，再导入需要的模型。",symbol:"folder"){Button("在访达中查看"){NSWorkspace.shared.open(AppPaths.models)}}
                PreferenceDivider()
                PreferenceRow(title:"导入与校验",detail:"可以只导入一个模型；验证已安装模型的文件完整性。",symbol:"checkmark.shield"){HStack(spacing:8){Button("导入模型"){importModels()};Button("验证文件"){verify()}}}
                PreferenceDivider()
                PreferenceRow(title:"模型引擎",detail:"仅重启本地模型进程，窗口和权限保留。",symbol:"arrow.clockwise"){Button("重新启动"){app.engine.stop();app.startServices()}}
            }.disabled(app.busy || downloads.downloading)
            if !status.isEmpty{Text(status).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true)}
        }.padding(.leading,20).padding(.trailing,24).padding(.bottom,28)}
        .task(id:downloads.revision){await downloads.refreshOverview()}
    }
    @ViewBuilder private func modelRow(_ spec:ModelSpec)->some View{
        let overview=downloads.overview[spec.id]
        let size=overview.map{String(format:" · %.2f GB",Double($0.bytes)/1_000_000_000)} ?? ""
        PreferenceRow(title:spec.title+(spec.role=="asr" ? " · 必需":" · 选装"),detail:spec.detail+"\n"+spec.id+size,symbol:spec.role=="asr" ? "waveform":spec.role=="cleanup" ? "sparkles":"translate"){
            if overview?.installed==true{Label("已安装",systemImage:"checkmark.circle").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
            else if downloads.activeID==spec.id{Text("下载中").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
            else if let overview{Button(overview.hasPartial ? "继续下载":"下载"){downloads.start(spec)}.disabled(downloads.downloading || app.resourcesBusy)}
            else{Text("正在检查").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
        }
    }
    func verify(){
        guard !app.busy,!downloads.downloading else{return}
        app.resourcesBusy=true;status="正在验证已安装模型…"
        Task{do{
            let manifest=try ModelResources.manifest().filter{FileManager.default.fileExists(atPath:AppPaths.models.appendingPathComponent($0.key).path)}
            guard !manifest.isEmpty else{throw AppError.message("还没有安装模型，请先下载语音识别模型。")}
            try await Task.detached{try ModelResources.validate(AppPaths.models,manifest:manifest)}.value
            status="已安装的 \(manifest.count) 个模型均已通过完整性校验。"
        }catch{status=error.localizedDescription};app.resourcesBusy=false}
    }
    func importModels(){
        guard !app.busy,!downloads.downloading else{return}
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false;panel.prompt="导入模型"
        guard panel.runModal() == .OK,let selected=panel.url,!app.busy else{return}
        let single=downloads.specs.contains(where:{$0.id==selected.lastPathComponent})
        let url=single ? selected.deletingLastPathComponent():selected
        app.resourcesBusy=true;status="正在校验并导入选定模型，原文件保持不变。"
        app.engine.stop()
        Task{do{let all=try ModelResources.manifest();let manifest=single ? all.filter{$0.key==selected.lastPathComponent}:all;try await Task.detached{try ModelResources.importModels(from:url,manifest:manifest)}.value;downloads.revision+=1;status="模型已导入并通过校验，无需重启应用。"}catch{status=error.localizedDescription};app.resourcesBusy=false;app.startServices()}
    }
}
struct KeycapStrip:View {
    var keys:[String]
    var pressed=false
    var large=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View{
        HStack(spacing:8){ForEach(Array(keys.enumerated()),id:\.offset){_,key in
            Text(key).font(.system(size:key.count>2 ? 19:key.count==2 ? 22:30,weight:.semibold))
                .foregroundStyle(Color.blue)
                .frame(width:key.count>3 ? 82:56,height:60)
                .background(LinearGradient(colors:[Color(nsColor:.controlBackgroundColor),Color.blue.opacity(pressed ? 0.30:0.15)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.white.opacity(0.55),lineWidth:1))
                .padding(4).background(Color.blue.opacity(pressed ? 0.95:0.75),in:RoundedRectangle(cornerRadius:14))
                .shadow(color:Color.blue.opacity(pressed ? 0.24:0.10),radius:pressed ? 2:4,y:pressed ? 0:3).offset(y:pressed ? 2:0)
        }}.animation(reduceMotion ? nil:.easeOut(duration:0.10),value:keys)
        .accessibilityElement(children:.ignore).accessibilityLabel(keys.joined(separator:" + "))
    }
}
struct FloatingView:View {
    @ObservedObject var app:AppState
    var visualState:CapsuleMotionState{CapsuleMotionState.resolve(phase:app.phase,stage:app.stage,delivery:app.deliveryState)}
    var body:some View {
        Group {
            if app.overlayExpanded {
                ExpandedCapsuleCard(title:app.stage,collapse:{app.overlay?.setExpanded(false)}){
                    if app.busy{
                        CompactCapsuleFace(source:app.meter,state:visualState)
                    }else{
                        Text(app.latestRecord?.output.isEmpty==false ? String(app.latestRecord!.output.prefix(160)):app.notice).font(.callout).lineLimit(3)
                    }
                }footer:{
                    if app.busy{
                        HStack{Text(app.capturing ? "再按快捷键结束 · Esc 取消":"录音已保存，正在本机处理").font(.caption2).foregroundStyle(.secondary).lineLimit(1);Spacer();Button(app.capturing ? "结束":"取消"){if app.capturing{app.finish()}else{app.cancel()}}}
                    }else{
                        HStack{Button("复制"){copy()}.disabled(!hasCopyableResult);Button("查看历史"){history()};Spacer();Button("关闭"){app.overlay?.hide()}}
                    }
                }
            }else{
                CompactCapsuleFace(source:app.meter,state:visualState)
                .contentShape(Capsule()).onTapGesture{if app.capturing{app.finish()}else{app.overlay?.setExpanded(true)}}
                .help(app.phase=="preparing" ? "麦克风准备中，圆球展开为胶囊后开始说话；Esc 取消。":app.capturing ? "正在录音，再按快捷键或点击胶囊结束；Esc 取消。":app.phase=="working" ? app.stage+"，录音已保存，可点击查看详情。":"结果已保存，点击查看或复制。")
                .accessibilityElement(children:.ignore).accessibilityLabel("咸鱼说"+visualState.title).accessibilityAddTraits(.isButton)
            }
        }.tint(DianyuDesign.accent)
        .contextMenu {
            Button("展开详情"){app.overlay?.setExpanded(true)}
            if app.busy {Button("取消并保留录音"){app.cancel()}}
            else{Button("复制结果"){copy()}.disabled(!hasCopyableResult);Button("查看历史"){history()};Button("隐藏"){app.overlay?.hide()}}
        }
    }
    var hasCopyableResult:Bool{app.latestRecord.map{!$0.output.isEmpty || !$0.raw.isEmpty} ?? false}
    func copy(){if let r=app.latestRecord{Delivery.copy(r.output.isEmpty ? r.raw:r.output)}}
    func history(){app.page="历史";app.showMain?();app.overlay?.hide()}
}
@MainActor final class OverlayController {
    let panel:NSPanel
    private weak var app:AppState?
    private var dismiss:Task<Void,Never>?
    private var visibilityGeneration=0
    init(app:AppState){
        self.app=app
        panel=NSPanel(contentRect:NSRect(origin:.zero,size:OverlayLayout.compact),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating;panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.isMovableByWindowBackground=false
        panel.contentView=NSHostingView(rootView:FloatingView(app:app));panel.setAccessibilityTitle("咸鱼说录音胶囊")
    }
    func setExpanded(_ expanded:Bool){
        dismiss?.cancel();dismiss=nil;visibilityGeneration+=1;app?.overlayExpanded=expanded
        let frame=panel.frame,size=expanded ? OverlayLayout.expanded:OverlayLayout.compact
        panel.setFrame(NSRect(x:frame.midX-size.width/2,y:frame.minY,width:size.width,height:size.height),display:true)
    }
    func show(){
        setExpanded(false)
        let screen=NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? NSScreen.main
        if let frame=screen?.visibleFrame{panel.setFrame(OverlayLayout.capsuleFrame(in:frame),display:true)}
        panel.orderFrontRegardless()
        if let app,let delay=OverlayLayout.dismissDelay(phase:app.phase,delivery:app.deliveryState,cancelled:app.stage.contains("取消")){
            let generation=visibilityGeneration,session=app.latest,state=app.deliveryState
            dismiss=Task{[weak self]in
                do{try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000))}catch{return}
                guard let self,let app=self.app,!Task.isCancelled,self.visibilityGeneration==generation,
                      !app.busy,!app.overlayExpanded,app.phase=="result",app.latest==session,app.deliveryState==state else{return}
                RuntimeDiagnostics.event("overlay_auto_hidden",field:state)
                self.hide()
            }
        }
    }
    func hide(){dismiss?.cancel();dismiss=nil;visibilityGeneration+=1;panel.orderOut(nil)}
}
final class AudioReplay:NSObject,AVAudioPlayerDelegate {
    static let shared=AudioReplay();private var player:AVAudioPlayer?
    func play(_ url:URL){do{player=try AVAudioPlayer(contentsOf:url);player?.delegate=self;player?.play()}catch{NSSound.beep()}}
    func stop(){player?.stop();player=nil}
}
