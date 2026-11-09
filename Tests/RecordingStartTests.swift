import Foundation
import AVFoundation

@main struct RecordingStartTests {
 @MainActor static func main()async throws{
  var count=0
  func check(_ pass:Bool,_ name:String){precondition(pass,name);count+=1}
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuStart-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let format=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1)!
  func buffer(_ value:Float,frames:Int=1600)->AVAudioPCMBuffer{let b=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(frames))!;b.frameLength=AVAudioFrameCount(frames);for i in 0..<frames{b.floatChannelData![0][i]=value};return b}
  let recorder=Recorder(),url=root.appendingPathComponent("first.wav"),owner=try recorder.testArmWriter(url,format:format)
  let first=Task{@MainActor in await recorder.waitForAudio()},second=Task{@MainActor in await recorder.waitForAudio()}
  let zero=buffer(0);recorder.testFeed(zero,owner:owner);recorder.testFeed(zero,owner:owner)
  try await Task.sleep(nanoseconds:60_000_000)
  check(recorder.readinessAudit["usable_audio_received"]as?Bool==false,"Digital startup zeros never announce recording readiness")
  check(abs(recorder.duration-0.2)<0.0001,"Startup silence is still saved, not trimmed from the original")
  let speech=buffer(0.013,frames:320);speech.floatChannelData![0][0]=0.29
  recorder.testFeed(speech,owner:owner)
  let ready1=await first.value,ready2=await second.value
  check(ready1 && ready2,"Independent warm/start waiters can observe the same first valid PCM")
  check(abs((recorder.readinessAudit["startup_digital_silence_seconds"]as!Double)-0.2)<0.0001,"Startup silence duration is audited")
  _=recorder.finish(keepWarm:false)
  let file=try AVAudioFile(forReading:url),read=AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length))!;try file.read(into:read)
  check(read.frameLength==3520,"Every initial frame is saved exactly once")
  check(read.floatChannelData![0][3200]==0.29,"The very first audible sample survives startup intact")
  check(read.floatChannelData![0][3519]==0.013,"The end of the first spoken buffer survives intact")
  check(CaptureReadiness.hasSignal(buffer(0.0000001)),"Readiness is not a normal-volume speech gate")
  check(!CaptureReadiness.hasSignal(buffer(.nan)),"Invalid PCM cannot claim microphone readiness")
  let stereo=AVAudioFormat(standardFormatWithSampleRate:16000,channels:2)!,right=AVAudioPCMBuffer(pcmFormat:stereo,frameCapacity:160)!
  right.frameLength=160;for c in 0..<2{for i in 0..<160{right.floatChannelData![c][i]=c==0 ? 0:0.01}}
  check(CaptureReadiness.hasSignal(right),"Valid right-channel audio also establishes readiness")
  let next=try recorder.testArmWriter(root.appendingPathComponent("cancel.wav"),format:format)
  let cancelled=Task{@MainActor in await recorder.waitForAudio()};try await Task.sleep(nanoseconds:30_000_000);recorder.shutdown()
  check(await cancelled.value==false,"Retirement cancels an old readiness wait promptly")
  let fresh=try recorder.testArmWriter(root.appendingPathComponent("next.wav"),format:format)
  recorder.testFeed(speech,owner:next);check(recorder.duration==0,"A retired callback cannot write a new first syllable")
  recorder.testFeed(speech,owner:fresh);check(abs(recorder.duration-0.02)<0.0001,"The new capture owner receives its own first buffer")
  _=recorder.finish(keepWarm:false)
  print("Recording startup/readiness/first-PCM checks passed:",count)
 }
}
