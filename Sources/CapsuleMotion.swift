import AppKit
import SwiftUI

/// Overlay-only visual states. These never change the recording/ASR state machine.
enum CapsuleMotionState:String,CaseIterable {
    case preparing,recording,recognizing,cleaning,translating,filled,clipboard,pending,saved,cancelled,recoverable
    static func resolve(phase:String,stage:String,delivery:String)->Self{
        if phase=="preparing"{return .preparing}
        if phase=="recording"{return .recording}
        if phase=="working"{
            if stage.contains("翻译"){return .translating}
            if ["整理","段落","填入","完成"].contains(where:stage.contains){return .cleaning}
            return .recognizing
        }
        if phase=="error"{return .recoverable}
        if stage.contains("取消"){return .cancelled}
        return delivery=="verified" ? .filled:delivery=="clipboard" ? .clipboard:delivery=="unverified" ? .pending:.saved
    }
    var title:String{switch self{
    case .preparing:return "准备麦克风"
    case .recording:return "正在录音"
    case .recognizing:return "正在识别"
    case .cleaning:return "正在完成"
    case .translating:return "正在翻译"
    case .filled:return "已填入"
    case .clipboard:return "已复制，可粘贴"
    case .pending:return "待确认，可查看"
    case .saved:return "已保存，可找回"
    case .cancelled:return "已取消"
    case .recoverable:return "录音已保留，可恢复"
    }}
    var active:Bool{[.preparing,.recording,.recognizing,.cleaning,.translating].contains(self)}
    var compactTitle:String{switch self{
    case .preparing:return "准备中"
    case .clipboard:return "已复制"
    case .pending:return "待确认"
    case .saved:return "已保存"
    case .recoverable:return "可恢复"
    default:return title
    }}
    var symbol:String?{switch self{
    case .filled:return "checkmark"
    case .clipboard:return "doc.on.clipboard"
    case .pending:return "questionmark"
    case .saved:return "checkmark"
    case .cancelled:return "xmark"
    case .recoverable:return "exclamationmark"
    default:return nil
    }}
}
/// Conventional rounded audio bars, each returning to a dot in silence.
/// Recording is driven by real level. Processing patterns never impersonate audio.
enum CapsuleDotRenderer {
    static let columns=9,rows=1,count=columns
    static func levels(state:CapsuleMotionState,level:Double,time:Double,reduced:Bool,columns audio:[Double]?=nil)->[Double]{
        let t=reduced ? 0:time,voice=level.isFinite ? min(1,max(0,level)):0
        return (0..<count).map{index in
            let column=index,x=Double(column)/Double(columns-1)
            let energy:Double
            switch state{
            case .recording:
                let raw=audio?.count==columns ? audio![column]:voice
                let amplitude=raw.isFinite ? min(1,max(0,raw)):0
                return column==columns/2 ? 0.46+0.54*amplitude:min(1,amplitude*4)
            case .recognizing:
                let center=reduced ? 0.64:(t*0.40).truncatingRemainder(dividingBy:1.4)-0.2
                energy=exp(-pow((x-center)/0.30,2))
            case .cleaning:
                energy=reduced ? 0.55:0.30+0.46*(0.5+0.5*cos(x*Double.pi*2-t*1.4))
            case .translating:
                energy=(0.25+0.65*(0.5+0.5*sin(x*5.6+t*1.7)))
            case .preparing:
                energy=reduced ? 0.32:0.20+0.20*(0.5+0.5*sin(t*1.7+x*2))
            default:energy=0.08
            }
            return min(1,max(0,0.12+0.88*energy))
        }
    }
    static func heights(state:CapsuleMotionState,level:Double,time:Double,reduced:Bool,columns audio:[Double]?=nil)->[Double]{
        let voice=level.isFinite ? min(1,max(0,level)):0
        if state == .recording{return audio?.count==columns ? audio!.map{min(1,max(0,$0.isFinite ? $0:0))}:Array(repeating:voice,count:columns)}
        switch state{
        case .preparing:return Array(repeating:0.25,count:columns)
        case .recognizing,.translating,.cleaning:return Array(repeating:0,count:columns)
        default:return Array(repeating:0,count:columns)
        }
    }
    static func ringTarget(_ state:CapsuleMotionState)->Double{[.preparing,.cleaning,.translating].contains(state) ? 1:0}
    static func draw(_ context:CGContext,bounds:CGRect,state:CapsuleMotionState,level:Double,time:Double,reduced:Bool,values:[Double]?=nil,heights:[Double]?=nil,shape:Double?=nil,expansion:Double?=nil){
        guard bounds.width>0,bounds.height>0 else{return}
        context.saveGState();defer{context.restoreGState()}
        let opened=min(1,max(0,expansion ?? (state == .preparing ? 0:1)))
        let width=bounds.height+(bounds.width-bounds.height)*opened
        let bodyBounds=CGRect(x:bounds.midX-width/2,y:bounds.minY,width:width,height:bounds.height)
        let body=CGPath(roundedRect:bodyBounds,cornerWidth:bounds.height/2,cornerHeight:bounds.height/2,transform:nil)
        context.addPath(body);context.setFillColor(NSColor(srgbRed:0.045,green:0.045,blue:0.048,alpha:1).cgColor);context.fillPath()
        let line=bodyBounds.insetBy(dx:0.5,dy:0.5)
        context.addPath(CGPath(roundedRect:line,cornerWidth:line.height/2,cornerHeight:line.height/2,transform:nil))
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor);context.setLineWidth(0.5);context.strokePath()
        let dots=values?.count==count ? values!:levels(state:state,level:level,time:time,reduced:reduced)
        let columnHeights=heights?.count==columns ? heights!:self.heights(state:state,level:level,time:time,reduced:reduced)
        let scale=min(1,bounds.height/36),pitch=5.2*scale,radius=1.25*scale
        let mix=min(1,max(0,shape ?? ringTarget(state))),rotation=reduced ? 0:time*0.65
        let center=CGPoint(x:bounds.midX+20*scale*opened,y:bounds.midY)
        for column in 0..<columns{
            let intensity=dots[column]
            context.setFillColor(NSColor.white.withAlphaComponent(intensity).cgColor)
            let angle=Double(column)/Double(columns)*Double.pi*2+rotation
            let lineX=(Double(column)-4)*pitch
            let x=center.x+lineX*(1-mix)+cos(angle)*5*scale*mix,y=center.y+sin(angle)*5*scale*mix
            let height=radius*2+10*scale*columnHeights[column]*(1-mix)
            context.addPath(CGPath(roundedRect:CGRect(x:x-radius,y:y-height/2,width:radius*2,height:height),cornerWidth:radius,cornerHeight:radius,transform:nil));context.fillPath()
        }
    }
}
/// Continuously retarget point brightness instead of restarting an animation on a
/// stage change. Interruption by a faster following stage remains position-continuous.
struct CapsuleDotDynamics {
    private(set) var values=[Double](repeating:0.12,count:CapsuleDotRenderer.count)
    private(set) var heights=[Double](repeating:0,count:CapsuleDotRenderer.columns)
    private(set) var shape=0.0
    private(set) var expansion=0.0
    mutating func beginPreparation(){expansion=0}
    mutating func advance(state:CapsuleMotionState,level:Double,time:Double,dt:Double,reduced:Bool,columns audio:[Double]?=nil){
        let target=CapsuleDotRenderer.levels(state:state,level:level,time:time,reduced:reduced,columns:audio)
        let goal=CapsuleDotRenderer.heights(state:state,level:level,time:time,reduced:reduced,columns:audio)
        guard !reduced else{values=target;heights=goal;shape=CapsuleDotRenderer.ringTarget(state);expansion=state == .preparing ? 0:1;return}
        let delta=dt.isFinite ? min(0.05,max(0,dt)):0
        shape+=(CapsuleDotRenderer.ringTarget(state)-shape)*(1-exp(-delta/0.18))
        expansion+=((state == .preparing ? 0.0:1.0)-expansion)*(1-exp(-delta/0.06))
        for i in values.indices{
            let tau=state == .recording ? (target[i]>values[i] ? 0.045:0.085):0.15
            values[i]+=(target[i]-values[i])*(1-exp(-delta/tau))
        }
        for i in heights.indices{
            let tau=state == .recording ? (goal[i]>heights[i] ? 0.045:0.065):0.15
            heights[i]+=(goal[i]-heights[i])*(1-exp(-delta/tau))
        }
    }
}
struct CapsuleAurora:NSViewRepresentable {
    let source:WaveformSignal
    let state:CapsuleMotionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeNSView(context:Context)->WaveformSurface{WaveformSurface()}
    func updateNSView(_ view:WaveformSurface,context:Context){view.configure(source:source,phase:state == .recording ? "recording":state.active ? "working":"result",compact:true,reduced:reduceMotion,aurora:state)}
}
struct CompactCapsuleFace:View {
    let source:WaveformSignal
    let state:CapsuleMotionState
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body:some View{
        CapsuleAurora(source:source,state:state).frame(width:OverlayLayout.compact.width,height:OverlayLayout.compact.height)
            .overlay{
                GeometryReader{geometry in
                    let middle=geometry.size.height/2
                    Text(state.compactTitle).font(.system(size:10.5,weight:.medium)).foregroundStyle(.white.opacity(0.94))
                        .frame(width:52,alignment:.leading).position(x:38,y:middle)
                    Image(systemName:state.symbol ?? (state == .recording ? "stop.fill":"ellipsis"))
                        .font(.system(size:state.symbol == nil ? 9:12,weight:.semibold)).foregroundStyle(.white.opacity(0.9)).position(x:148,y:middle)
                }.allowsHitTesting(false).opacity(state == .preparing ? 0:1)
                    .animation(reduced ? nil:.easeOut(duration:0.12).delay(state == .preparing ? 0:0.12),value:state == .preparing)
            }
            .contentShape(Capsule())
    }
}

/// Header and actions reserve fixed rows; only the middle content area grows.
struct ExpandedCapsuleCard<Content:View,Footer:View>:View {
    let title:String
    let collapse:()->Void
    let content:()->Content
    let footer:()->Footer
    init(title:String,collapse:@escaping()->Void,@ViewBuilder content:@escaping()->Content,@ViewBuilder footer:@escaping()->Footer){self.title=title;self.collapse=collapse;self.content=content;self.footer=footer}
    var body:some View{
        VStack(alignment:.leading,spacing:10){
            HStack{
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                Spacer(minLength:8)
                Button(action:collapse){Image(systemName:"chevron.down")}.buttonStyle(.plain).accessibilityLabel("收起浮窗")
            }.frame(height:20).accessibilityIdentifier("capsule.card.header")
            content().frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            footer().frame(maxWidth:.infinity).frame(height:28).accessibilityIdentifier("capsule.card.footer")
        }.padding(14)
            .frame(width:OverlayLayout.expanded.width,height:OverlayLayout.expanded.height,alignment:.topLeading)
            .background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))
    }
}
