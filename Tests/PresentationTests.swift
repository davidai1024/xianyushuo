import Foundation
import AppKit

@main struct PresentationTests {
    static func main(){
        var count=0
        func check(_ ok:Bool,_ name:String){precondition(ok,name);count+=1}
        var a=WaveformEnvelope(),b=WaveformEnvelope()
        for _ in 0..<60{a.advance(target:Array(repeating:0.8,count:34),dt:1.0/60)}
        for _ in 0..<120{b.advance(target:Array(repeating:0.8,count:34),dt:1.0/120)}
        check(zip(a.values,b.values).allSatisfy{abs($0-$1)<0.000001},"Display-rate-independent envelope")
        var smooth=WaveformEnvelope();smooth.advance(target:Array(repeating:1,count:34),dt:1.0/120)
        check(smooth.values.allSatisfy{$0>0 && $0<0.3},"Attack interpolates instead of jumping")
        let first=smooth.values[0];smooth.advance(target:Array(repeating:0,count:34),dt:1.0/120)
        check(smooth.values[0]>0 && smooth.values[0]<first,"Release decays smoothly")
        var clamped=WaveformEnvelope();clamped.advance(target:Array(repeating:4,count:34),dt:10)
        check(clamped.values.allSatisfy{$0>=0 && $0<=1},"Amplitude and stalled-frame delta bounded")
        let signal=WaveformSignal();signal.update([0.5]);check(signal.snapshot(now:ProcessInfo.processInfo.systemUptime)==[0.5],"Meter signal receives real levels")
        check(signal.snapshot(now:ProcessInfo.processInfo.systemUptime+1)==[0],"Stale microphone level decays to silence")
        let lo=WaveformEnvelope.intensity(amplitude:0.49,distance:0.5),hi=WaveformEnvelope.intensity(amplitude:0.51,distance:0.5)
        check(lo>0 && hi<1 && hi-lo<0.1,"Soft particle edges remove binary flicker")
        func event(_ key:UInt16,_ flags:NSEvent.ModifierFlags,_ text:String)->NSEvent{
            NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:key)!
        }
        check(ShortcutInput.binding(event(2,[.control,.shift],"D"))?.label=="⌃⇧D","Combination stores physical label")
        check(ShortcutInput.binding(event(17,[.option],"†"))?.label=="⌥T","Option character does not replace key name")
        check(ShortcutInput.binding(event(49,[]," "))==nil,"Bare space cannot steal typing")
        check(ShortcutInput.binding(event(100,[],""))?.label=="F8","Bare function key supported")
        check(ShortcutInput.binding(event(0,[],"a"))==nil,"Bare letter cannot steal typing")
        print("Presentation checks passed:",count)
    }
}
