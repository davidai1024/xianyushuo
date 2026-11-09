import AppKit
import SwiftUI
import Foundation

private struct PreviewMeterFrame:Decodable {var dt:Double;var samples:[Double]}
@MainActor final class CapsulePreviewModel:ObservableObject {
    let signal=WaveformSignal()
    @Published var state=CapsuleMotionState.recording
    @Published var quiet=false
    @Published var cardCase=0
    private var timer:Timer?
    private var trace:[PreviewMeterFrame]=[]
    private var ends:[Double]=[]
    private var began=ProcessInfo.processInfo.systemUptime
    var sampleLabel:String{trace.isEmpty ? "模拟音量，不使用麦克风":"原录音音量回放，不使用麦克风"}
    var cardTitle:String{["未识别到语音","已填入","已保存","正在完成"][cardCase]}
    var cardText:String{["未识别到文字，录音已保留，可重试。","这是一段短结果。",String(repeating:"这是一段较长的结果，用来检查正文区域和底部按钮的位置。",count:8),""][cardCase]}
    init(){
        if let url=Bundle.main.url(forResource:"MeterTrace",withExtension:"json"),let data=try? Data(contentsOf:url),let frames=try? JSONDecoder().decode([PreviewMeterFrame].self,from:data){trace=frames;var time=0.0;ends=frames.map{time+=$0.dt;return time}}
        timer=Timer.scheduledTimer(withTimeInterval:0.02,repeats:true){[weak self]_ in Task{@MainActor in self?.update()}}
    }
    private func update(){
        if quiet{signal.update(Array(repeating:0,count:34));return}
        let time=ProcessInfo.processInfo.systemUptime-began
        if let duration=ends.last,duration>0{
            let at=time.truncatingRemainder(dividingBy:duration+0.8)
            if let index=ends.firstIndex(where:{$0>at}){signal.update(trace[index].samples)}else{signal.reset()}
        }else{
            let levels=[0.0,0.18,0.45,0.72,0.28,0.0,0.0]
            signal.update(Array(repeating:levels[Int(time/0.32)%levels.count],count:34))
        }
    }
    deinit{timer?.invalidate()}
}
struct CapsulePreviewView:View {
    @ObservedObject var model:CapsulePreviewModel
    var body:some View{
        VStack(spacing:16){
            Text("声纹与卡片布局预览").font(.system(size:20,weight:.semibold))
            Text(model.sampleLabel).font(.system(size:12)).foregroundStyle(.secondary)
            CompactCapsuleFace(source:model.signal,state:model.state).frame(height:50)
            HStack{ForEach([CapsuleMotionState.preparing,.recording,.recognizing,.cleaning,.translating],id:\.self){state in Button(state.title){model.state=state}}}
            Button(model.quiet ? "继续原录音回放":"模拟停顿"){model.quiet.toggle()}
            Divider().padding(.vertical,4)
            HStack{ForEach(Array(["无语音","短结果","长结果","处理中"].enumerated()),id:\.offset){index,title in Button(title){model.cardCase=index}}}
            ExpandedCapsuleCard(title:model.cardTitle,collapse:{}){
                if model.cardCase==3{CompactCapsuleFace(source:model.signal,state:.cleaning)}else{Text(model.cardText).font(.callout).lineLimit(3)}
            }footer:{
                HStack{Button("复制"){}.disabled(model.cardCase==0);Button("查看历史"){};Spacer();Button("关闭"){}}
            }
        }.padding(28).frame(width:660,height:560).background(Color(white:0.16)).foregroundStyle(.white)
    }
}
@MainActor final class CapsulePreviewDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    let model=CapsulePreviewModel()
    var window:NSWindow?
    func applicationDidFinishLaunching(_ notification:Notification){
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:560),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="咸鱼说声纹与卡片预览";window.isReleasedWhenClosed=false;window.delegate=self
        window.contentView=NSHostingView(rootView:CapsulePreviewView(model:model));window.center();window.makeKeyAndOrderFront(nil);self.window=window
        NSApp.activate(ignoringOtherApps:true)
    }
    func windowShouldClose(_ sender:NSWindow)->Bool{NSApp.terminate(nil);return false}
}
@main struct CapsuleMotionFixture {
    @MainActor static func main()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuCapsuleMotionFixture034")
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        let app=NSApplication.shared;app.setActivationPolicy(.regular);app.appearance=NSAppearance(named:.darkAqua)
        let delegate=CapsulePreviewDelegate();app.delegate=delegate;app.run();withExtendedLifetime(delegate){}
    }
}
