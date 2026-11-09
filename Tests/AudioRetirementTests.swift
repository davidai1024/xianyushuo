import AppKit
import AVFoundation

// No real microphone, permissions or production data. The supplied helpers
// exist only in the temporary test compilation of Recorder.swift.
@main struct AudioRetirementTests {
    @MainActor static func main()async throws{
        var checks=0
        func check(_ ok:Bool,_ message:String){precondition(ok,message);checks+=1}
        let retirement=AudioRetirement(),gate=DispatchSemaphore(value:0),entered=DispatchSemaphore(value:0)
        let start=ProcessInfo.processInfo.systemUptime
        var mainCompletion=false
        retirement.submit({entered.signal();gate.wait()},finished:{precondition(Thread.isMainThread);mainCompletion=true})
        check(ProcessInfo.processInfo.systemUptime-start<0.1,"Teardown never blocks capture finalization")
        check(entered.wait(timeout:.now()+1) == .success,"Owned cleanup scheduled")
        check(retirement.pending,"Busy cleanup tracked")
        var completedWait=false
        let waiter=Task{@MainActor in await retirement.wait();completedWait=true}
        try await Task.sleep(nanoseconds:30_000_000)
        check(!completedWait && !mainCompletion,"Start waits for hardware retirement")
        gate.signal();await waiter.value
        for _ in 0..<50 where !mainCompletion{try await Task.sleep(nanoseconds:1_000_000)}
        check(completedWait && mainCompletion && !retirement.pending,"Wait and main-thread completion settle")
        let gate2=DispatchSemaphore(value:0),entered2=DispatchSemaphore(value:0),gate3=DispatchSemaphore(value:0),entered3=DispatchSemaphore(value:0)
        retirement.submit({entered2.signal();gate2.wait()});retirement.submit({entered3.signal();gate3.wait()})
        check(entered2.wait(timeout:.now()+1) == .success,"First cleanup active")
        check(entered3.wait(timeout:.now()+0.02) == .timedOut,"Cleanup ownership serialized")
        gate2.signal();check(entered3.wait(timeout:.now()+1) == .success && retirement.pending,"Pending includes queued cleanup")
        gate3.signal();await retirement.wait();check(!retirement.pending,"All retirements finished")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuRetirement-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
        let recorder=Recorder(),first=root.appendingPathComponent("first.wav"),second=root.appendingPathComponent("second.wav")
        let format=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1)!,buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1600)!
        buffer.frameLength=1600;for i in 0..<1600{buffer.floatChannelData![0][i]=0.01}
        var meterCalls=0;recorder.onLevels={_ in meterCalls+=1}
        let oldOwner=try recorder.testOpenFile(first,format:format)
        recorder.testFeed(buffer,owner:oldOwner)
        check(abs(recorder.duration-0.1)<0.00001,"First capture received PCM")
        let seconds=recorder.finish(keepWarm:false,releaseAsynchronously:true)
        let firstLength=try AVAudioFile(forReading:first).length
        check(abs(seconds-0.1)<0.00001 && firstLength==1600,"Final PCM durable before hardware release")
        let newOwner=try recorder.testOpenFile(second,format:format)
        check(newOwner != oldOwner,"Capture generation rotated")
        recorder.testFeed(buffer,owner:oldOwner)
        check(recorder.duration==0,"Retired callback cannot write next recording")
        try await Task.sleep(nanoseconds:20_000_000)
        check(meterCalls==0,"Queued retired meter cannot animate next recording")
        recorder.testFeed(buffer,owner:newOwner)
        check(abs(recorder.duration-0.1)<0.00001,"Next owner can write")
        _=recorder.finish(keepWarm:false,releaseAsynchronously:true)
        check((try AVAudioFile(forReading:second)).length==1600,"No duplicated stale PCM")
        print("Audio retirement/ownership checks passed:",checks)
    }
}
