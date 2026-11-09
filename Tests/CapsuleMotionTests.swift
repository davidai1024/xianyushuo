import Foundation
import AppKit
import SwiftUI

@main struct CapsuleMotionTests {
    static func main(){
        _=NSApplication.shared
        var checks=0
        func check(_ truth:Bool,_ label:String){if !truth{FileHandle.standardError.write(Data(("FAILED: "+label+"\n").utf8))};precondition(truth,label);checks+=1}
        func render(_ state:CapsuleMotionState,level:Double,time:Double,reduced:Bool=false)->[UInt8]{
            let context=CGContext(data:nil,width:336,height:72,bitsPerComponent:8,bytesPerRow:336*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x:2,y:2)
            CapsuleDotRenderer.draw(context,bounds:CGRect(x:0,y:0,width:168,height:36),state:state,level:level,time:time,reduced:reduced)
            return Array(UnsafeBufferPointer(start:context.data!.assumingMemoryBound(to:UInt8.self),count:336*72*4))
        }
        func delta(_ a:[UInt8],_ b:[UInt8])->Double{zip(a,b).reduce(0.0){$0+abs(Double($1.0)-Double($1.1))}/Double(a.count)/255}
        let quiet=render(.recording,level:0.05,time:1),loud=render(.recording,level:0.85,time:1)
        check(CapsuleDotRenderer.count==9,"Nine rounded bars replace the point matrix")
        let silent=CapsuleDotRenderer.levels(state:.recording,level:0,time:1,reduced:false)
        check(silent.filter{$0>0}.count==1 && silent[4]>0,"Silence is a single central dot")
        let preparing=render(.preparing,level:0,time:1)
        check(preparing[(36*336+80)*4+3]==0 && preparing[(36*336+168)*4+3]>0,"Preparation occupies one centered small orb, not an early recording pill")
        check(delta(quiet,loud)>0.001,"Real voice visibly changes point brightness")
        check(quiet[3]==0 && quiet[(71*336+335)*4+3]==0,"Rounded pill corners stay transparent")
        check(quiet[(36*336+80)*4+3]==255,"Black body remains opaque on a light desktop")
        check(quiet[(36*336+80)*4]<20,"Black background does not become a gray glowing bar")
        check(stride(from:0,to:loud.count,by:4).allSatisfy{loud[$0]==loud[$0+1] && abs(Int(loud[$0])-Int(loud[$0+2]))<=2},"Reference is monochrome rather than the previous rainbow")
        check(render(.recording,level:0,time:1)==render(.recording,level:0,time:2),"Silence does not fake speech")
        let quietPCM=CapsuleVisualResponse.level(Array(repeating:6.0/54,count:34))
        check(CapsuleVisualResponse.level(Array(repeating:0,count:34))==0,"Digital silence stays at the center dot")
        check(quietPCM>0.20 && delta(render(.recording,level:0,time:1),render(.recording,level:quietPCM,time:1))>0.0005,
              "Quiet input at -54 dBFS creates visible bars")
        check(render(.recording,level:0.5,time:1,reduced:true)==render(.recording,level:0.5,time:99,reduced:true),"Reduce Motion removes decorative travel")
        for state in CapsuleMotionState.allCases{
            let levels=CapsuleDotRenderer.levels(state:state,level:0.5,time:2,reduced:false)
            check(levels.count==9 && levels.allSatisfy{$0.isFinite && $0>=0 && $0<=1},"Wave targets stay finite and bounded")
            check(!state.compactTitle.isEmpty,"Every state retains plain-language feedback")
        }
        for state in [CapsuleMotionState.recognizing,.cleaning,.translating,.preparing]{
            check(render(state,level:0,time:1)==render(state,level:1,time:1),"Processing never impersonates live audio")
            check(delta(render(state,level:0,time:1),render(state,level:0,time:1.5))>0.0001,"Active processing is visibly moving")
        }
        check(delta(render(.recognizing,level:0,time:1,reduced:true),render(.cleaning,level:0,time:1,reduced:true))>0.0001,"Recognition and cleanup remain distinct with reduced motion")
        var dynamics=CapsuleDotDynamics()
        for _ in 0..<120{dynamics.advance(state:.recording,level:0.8,time:1,dt:1/120,reduced:false)}
        let before=dynamics.values
        dynamics.advance(state:.recognizing,level:0,time:1,dt:0,reduced:false)
        check(before==dynamics.values,"A stage change cannot reset or teleport the existing dots")
        dynamics.advance(state:.recognizing,level:0,time:1,dt:1/120,reduced:false)
        check(zip(before,dynamics.values).allSatisfy{abs($0-$1)<0.08},"First transition frame is continuous")
        let interrupted=dynamics.values
        let priorShape=dynamics.shape
        dynamics.advance(state:.cleaning,level:0,time:1,dt:0,reduced:false)
        check(interrupted==dynamics.values,"A fast following stage retargets the current pose")
        check(dynamics.shape==priorShape,"Processing shape never teleports on transition")
        for _ in 0..<120{dynamics.advance(state:.cleaning,level:0,time:1,dt:1/120,reduced:false)}
        let goal=CapsuleDotRenderer.levels(state:.cleaning,level:0,time:1,reduced:false)
        check(zip(goal,dynamics.values).allSatisfy{abs($0-$1)<0.01},"Transition settles to the actual stage pattern")
        check(dynamics.shape>0.99,"Cleanup settles to a distinct small ring")
        dynamics.beginPreparation();dynamics.advance(state:.preparing,level:0,time:1,dt:1/60,reduced:false)
        check(dynamics.expansion==0,"New microphone preparation starts as a ball")
        dynamics.advance(state:.recording,level:0,time:1,dt:0,reduced:false)
        check(dynamics.expansion==0,"Readiness retargets without a geometry jump")
        for _ in 0..<12{dynamics.advance(state:.recording,level:0,time:1,dt:1/60,reduced:false)}
        check(dynamics.expansion>0.96,"A ready microphone expands gently into the recording pill")
        dynamics.advance(state:.cleaning,level:Double.nan,time:1,dt:Double.nan,reduced:false)
        check(dynamics.values.allSatisfy{$0.isFinite},"Invalid visual input cannot poison the display")
        check(CapsuleMotionState.resolve(phase:"preparing",stage:"",delivery:"") == .preparing,"Preparing has its own feedback")
        check(CapsuleMotionState.resolve(phase:"recording",stage:"",delivery:"") == .recording,"Real recording has its own feedback")
        check(CapsuleMotionState.resolve(phase:"working",stage:"正在填入",delivery:"") == .cleaning,"Insertion shares the cleanup animation")
        check(CapsuleMotionState.resolve(phase:"working",stage:"正在整理",delivery:"") == .cleaning,"Cleanup shares the finalization stage")
        check(CapsuleMotionState.resolve(phase:"working",stage:"正在完成",delivery:"") == .cleaning,"Canonical finalization title keeps the same animation")
        for label in ["正在轻整理","正在整理","正在整理段落","正在填入"]{
            check(OverlayLayout.processingTitle(label)=="正在完成","No intermediate cleanup/insertion title: "+label)
            check(CapsuleMotionState.resolve(phase:"working",stage:OverlayLayout.processingTitle(label),delivery:"").title=="正在完成","Compact/expanded status agree: "+label)
        }
        check(CapsuleMotionState.resolve(phase:"working",stage:"正在翻译",delivery:"") == .translating,"Translation is separate")
        check(CapsuleMotionState.resolve(phase:"working",stage:"正在识别",delivery:"") == .recognizing,"Recognition is separate")
        check(CapsuleMotionState.resolve(phase:"result",stage:"",delivery:"unverified") == .pending,"Unconfirmed insertion never shows a success tick")
        check(CapsuleMotionState.resolve(phase:"error",stage:"",delivery:"verified") == .recoverable,"Error overrides stale prior delivery status")
        check(CapsuleMotionState.resolve(phase:"result",stage:"已取消",delivery:"verified") == .cancelled,"Cancel cannot display the previous result's filled state")
        for visible in [CGRect(x:0,y:0,width:1440,height:900),CGRect(x:-1920,y:40,width:1920,height:1040),CGRect(x:0,y:-900,width:1024,height:768)]{
            let capsule=OverlayLayout.capsuleFrame(in:visible)
            check(capsule.size==CGSize(width:168,height:36),"Smaller capsule preserves readable space")
            check(visible.contains(capsule),"Capsule stays above Dock in every display coordinate space")
        }
        print("Capsule rendering/state/placement checks passed:",checks)
    }
}
