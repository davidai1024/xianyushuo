import Foundation

@main struct RecordingTailTests {
    @MainActor static func main()async{
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        check(RecordingTail.seconds(bufferFrames:4800,sampleRate:48000)==0.2,"Two observed 100ms buffers get 200ms tail")
        check(RecordingTail.seconds(bufferFrames:2400,sampleRate:24000)==0.2,"Bluetooth sample rate uses actual frames")
        check(RecordingTail.seconds(bufferFrames:1024,sampleRate:48000)==0.12,"Short tap keeps a small lower bound")
        check(RecordingTail.seconds(bufferFrames:48000,sampleRate:48000)==0.22,"Abnormal callback size cannot add a long pause")
        for rate in [0.0,-1,.infinity,.nan]{check(RecordingTail.seconds(bufferFrames:1024,sampleRate:rate)==0.12,"Invalid rates remain bounded")}
        check(RecordingTail.seconds(bufferFrames:0,sampleRate:48000)==0.12,"No prior callback remains bounded")
        let controller=RecordingStopController();var finalized=0
        let stopTime=ProcessInfo.processInfo.systemUptime;var completionTime=stopTime
        controller.request(after:0.03){finalized+=1;completionTime=ProcessInfo.processInfo.systemUptime}
        check(controller.pending && finalized==0,"Stopping is asynchronous and keeps capture pending")
        try? await Task.sleep(nanoseconds:60_000_000)
        check(finalized==1 && !controller.pending && completionTime-stopTime>=0.03,"Completion cannot close the writer before the tail deadline")
        controller.request(after:0.03){finalized+=100}
        controller.cancel();try? await Task.sleep(nanoseconds:60_000_000)
        check(finalized==1 && !controller.pending,"Cancel cannot later restart inference")
        controller.request(after:0.04){finalized+=100}
        controller.request(after:0){finalized+=1}
        check(finalized==2 && !controller.pending,"Device change or sleep flushes immediately")
        try? await Task.sleep(nanoseconds:70_000_000)
        check(finalized==2,"Replaced delayed completion cannot execute twice")
        controller.request(after:0.03){finalized+=1}
        var unrelatedShortcutStartToken=0
        unrelatedShortcutStartToken+=1
        try? await Task.sleep(nanoseconds:60_000_000)
        check(unrelatedShortcutStartToken==1 && finalized==3 && !controller.pending,"Typing after stop cannot cancel the independent stop ticket")
        controller.request(after:0.04){finalized+=100}
        controller.request(after:0.01){finalized+=1}
        try? await Task.sleep(nanoseconds:70_000_000)
        check(finalized==4,"Only the newest recording completion can run")
        print("Recording tail checks passed:",checks)
    }
}
