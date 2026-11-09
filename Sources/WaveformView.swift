import AppKit
import SwiftUI
import QuartzCore

struct DotMatrix:NSViewRepresentable {
    let source:WaveformSignal
    var phase:String
    var compact=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context:Context)->WaveformSurface{WaveformSurface()}
    func updateNSView(_ view:WaveformSurface,context:Context){view.configure(source:source,phase:phase,compact:compact,reduced:reduceMotion)}
}
private final class WaveformPulse:NSObject {
    weak var view:WaveformSurface?
    @objc func tick(_ link:CADisplayLink){view?.advance(link)}
}
final class WaveformSurface:NSView {
    private var source=WaveformSignal()
    private var phase="idle",compact=false,reduced=false
    private var aurora:CapsuleMotionState?
    private var envelope=WaveformEnvelope()
    private var dotDynamics=CapsuleDotDynamics()
    private var voiceHistory=CapsuleVoiceHistory()
    private var time=0.0,lastTime=0.0
    private var link:CADisplayLink?
    private let pulse=WaveformPulse()
    private var samples:[Double]=[]
    private var draws=0
    private var observers:[NSObjectProtocol]=[]
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true;setAccessibilityElement(true);setAccessibilityRole(.image);pulse.view=self}
    required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    func configure(source:WaveformSignal,phase:String,compact:Bool,reduced:Bool,aurora:CapsuleMotionState?=nil){
        if self.phase != phase || self.aurora != aurora {saveMetrics();samples=[];draws=0;lastTime=0}
        if aurora == .recording && self.aurora != .recording{voiceHistory=CapsuleVoiceHistory()}
        if aurora == .preparing && self.aurora != .preparing{dotDynamics.beginPreparation()}
        self.source=source;self.phase=phase;self.compact=compact;self.reduced=reduced;self.aurora=aurora
        if let aurora,!aurora.active{dotDynamics.advance(state:aurora,level:0,time:time,dt:0,reduced:true)}
        setAccessibilityLabel(aurora?.title ?? (phase=="recording" ? "实时麦克风音量":"本地处理状态"))
        updateLink();needsDisplay=true
    }
    override func viewDidMoveToWindow(){
        super.viewDidMoveToWindow();link?.invalidate();link=nil
        observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]
        guard let window else{saveMetrics();return}
        let next=displayLink(target:pulse,selector:#selector(WaveformPulse.tick(_:)))
        next.preferredFrameRateRange=CAFrameRateRange(minimum:60,maximum:120,preferred:120)
        next.add(to:.main,forMode:.common);link=next
        observers.append(NotificationCenter.default.addObserver(forName:NSWindow.didChangeOcclusionStateNotification,object:window,queue:.main){[weak self]_ in self?.updateLink()})
        updateLink()
    }
    private func updateLink(){
        let active=["recording","working","preparing"].contains(phase)
        let paused = !active || window?.occlusionState.contains(.visible) != true
        // An occluded interval is not a displayed frame; resume from a fresh clock.
        if link?.isPaused != paused{lastTime=0}
        link?.isPaused=paused
        link?.preferredFrameRateRange=reduced ? CAFrameRateRange(minimum:10,maximum:10,preferred:10):CAFrameRateRange(minimum:60,maximum:120,preferred:120)
    }
    fileprivate func advance(_ display:CADisplayLink){
        let now=display.timestamp,dt=lastTime>0 ? now-lastTime:1/60
        if lastTime>0,dt>0,samples.count<1200 {samples.append(dt)}
        lastTime=now;time=now
        let actual=source.snapshot(now:ProcessInfo.processInfo.systemUptime)
        envelope.advance(target:actual,dt:dt)
        if let aurora{
            let level=CapsuleVisualResponse.level(actual)
            if aurora == .recording{voiceHistory.advance(level:level,dt:dt)}
            dotDynamics.advance(state:aurora,level:level,time:time,dt:dt,reduced:reduced,columns:aurora == .recording ? voiceHistory.columns:nil)
        }
        needsDisplay=true
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect);draws+=1
        if let aurora,let context=NSGraphicsContext.current?.cgContext{
            CapsuleDotRenderer.draw(context,bounds:bounds,state:aurora,level:CapsuleVisualResponse.level(envelope.values),time:time,reduced:reduced,values:dotDynamics.values,heights:dotDynamics.heights,shape:dotDynamics.shape,expansion:dotDynamics.expansion);return
        }
        let columns=compact ? 22:34,rows=compact ? 5:7
        let dx=bounds.width/Double(columns),dy=bounds.height/Double(rows)
        for column in 0..<columns {
            let i=min(33,column*34/columns)
            let amplitude:Double
            if phase=="recording" {amplitude=0.08+0.92*sqrt(envelope.values[i])}
            else if phase=="working" || phase=="preparing" {
                amplitude=reduced ? 0.45:0.50+0.40*sin(Double(column)*0.32-time*3.0)
            }else{amplitude=0.04}
            for row in 0..<rows {
                let distance=abs(Double(row)-Double(rows-1)/2)/(Double(rows-1)/2)
                let energy=WaveformEnvelope.intensity(amplitude:amplitude,distance:distance)
                let opacity=(compact ? 0.12:0.07)+(compact ? 0.88:0.90)*energy
                let radius=(compact ? 0.8:1.3)+energy*(compact ? 0.3:0.4)
                let color=compact ? NSColor.white:NSColor.labelColor
                color.withAlphaComponent(opacity).setFill()
                NSBezierPath(ovalIn:NSRect(x:(Double(column)+0.5)*dx-radius,y:(Double(row)+0.5)*dy-radius,width:2*radius,height:2*radius)).fill()
            }
        }
    }
    private func saveMetrics(){
        guard compact,samples.count>=30 else{return}
        let sorted=samples.sorted(),mean=samples.reduce(0,+)/Double(samples.count)
        let item:[String:Any]=["phase":phase,"state":aurora?.rawValue ?? phase,"renderer":aurora == nil ? "matrix":"audio_wave","callbacks":samples.count,"draws":draws,"mean_fps":1/mean,"p95_interval_ms":sorted[min(sorted.count-1,Int(Double(sorted.count)*0.95))]*1000,"reduce_motion":reduced]
        let url=AppPaths.root.appendingPathComponent("ui-render-metrics.json")
        var records=(try? JSONSerialization.jsonObject(with:Data(contentsOf:url)))as?[[String:Any]] ?? []
        records.append(item);records=Array(records.suffix(8))
        if let bytes=try? JSONSerialization.data(withJSONObject:records,options:[.prettyPrinted,.sortedKeys]){try? bytes.write(to:url,options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)}
        samples=[]
    }
    deinit {link?.invalidate();observers.forEach{NotificationCenter.default.removeObserver($0)}}
}
