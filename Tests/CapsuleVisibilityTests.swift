import Foundation
import AppKit

@main struct CapsuleVisibilityTests {
    static func main(){
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ label:String){if !value{FileHandle.standardError.write(Data(("FAILED: "+label+"\n").utf8))};precondition(value,label);checks+=1}
        func meter(_ value:Double)->Double{CapsuleVisualResponse.level(Array(repeating:value,count:34))}
        check(meter(0)==0 && meter(0.04)==0,"Silence is not manufactured into a voice signal")
        check(meter(0.18)>0.25 && meter(0.18)<0.4,"Quiet recording has usable visual response")
        check(meter(0.45)>0.7 && meter(0.45)<1,"Normal speech uses most of the visual range")
        check(meter(0.8)==1,"Loud input stays bounded")
        check(CapsuleVisualResponse.level([])==0,"Missing samples stay quiet")
        check(CapsuleVisualResponse.level([.nan,.infinity])==0,"Invalid samples cannot break rendering")
        check(CapsuleVisualResponse.level([-1,-3])==0,"Negative samples stay bounded")
        var previous=0.0
        for index in 0...100{let next=meter(Double(index)/100);check(next>=previous && next<=1,"Visual transfer is monotonic and bounded");previous=next}
        let silence=CapsuleDotRenderer.heights(state:.recording,level:0,time:1,reduced:false)
        let quiet=CapsuleDotRenderer.heights(state:.recording,level:meter(0.18),time:1,reduced:false)
        let normal=CapsuleDotRenderer.heights(state:.recording,level:meter(0.45),time:1,reduced:false)
        check(silence.allSatisfy{$0==0},"Silence collapses to a thin row, not an idle fake wave")
        check(quiet.min()!>0.25 && normal.min()!>quiet.max()!+0.3,"Quiet and normal speech have visibly different heights")
        check(CapsuleDotRenderer.levels(state:.recording,level:0.5,time:1,reduced:false)==CapsuleDotRenderer.levels(state:.recording,level:0.5,time:9,reduced:false),"Recording is driven by audio, never by a decorative sine clock")
        var history=CapsuleVoiceHistory(),dynamics=CapsuleDotDynamics()
        for tick in 0..<120{
            let input=tick<30 ? 0.0:tick<60 ? 0.8:0.0
            history.advance(level:input,dt:1/120)
            dynamics.advance(state:.recording,level:input,time:Double(tick)/120,dt:1/120,reduced:false,columns:history.columns)
            if tick==35{check(dynamics.heights.last!>0.35,"Visible response starts within50ms of speech")}
            if tick==55{check(dynamics.heights.max()!>0.7,"A spoken syllable makes a tall wave")}
        }
        check(dynamics.heights.max()!<0.08,"A pause returns to a flat line within500ms")
        var pulse=CapsuleVoiceHistory()
        for _ in 0..<12{pulse.advance(level:0.9,dt:1/120)}
        let newest=pulse.columns.last!
        for _ in 0..<6{pulse.advance(level:0,dt:1/120)}
        check(pulse.columns.dropLast().max()!>pulse.columns.last!,"Past syllable moves left while the newest position reflects silence")
        check(newest>0.8,"Full volume is not flattened")
        let source=WaveformSignal();source.update(Array(repeating:0.8,count:34))
        check(source.snapshot(now:ProcessInfo.processInfo.systemUptime+1).allSatisfy{$0==0},"Stopped audio callbacks cannot leave a stuck speaking indicator")
        print("Capsule visibility/quiet-voice response checks passed:",checks)
    }
}
