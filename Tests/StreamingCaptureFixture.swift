import Foundation
import AVFoundation
@main struct StreamingCaptureFixture {
 static func main()throws{
  let args=CommandLine.arguments
  guard args.count>=4 else{fatalError("source owner manifest [realtime]")}
  let url=URL(fileURLWithPath:args[1]),owner=args[2],out=URL(fileURLWithPath:args[3]),realtime=args.contains("realtime")
  let input=try AVAudioFile(forReading:url),format=input.processingFormat
  let capture=try StreamingCapture(owner:owner,format:format)
  func emit(_ object:[String:Any]){let data=try! JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]);FileHandle.standardOutput.write(data+Data([10]))}
  capture.onSegment={segment in emit(["event":"segment","payload":segment.payload,"index":segment.index,"at":Date().timeIntervalSince1970])}
  let begin=Date(),buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)!
  while input.framePosition<input.length{
   try input.read(into:buffer);if buffer.frameLength==0{break};capture.append(buffer)
   if realtime{let target=Double(input.framePosition)/format.sampleRate;let delay=target-Date().timeIntervalSince(begin);if delay>0{Thread.sleep(forTimeInterval:delay)}}
  }
  let stopped=Date().timeIntervalSince1970,segments=capture.finish()
  try JSONSerialization.data(withJSONObject:segments.map{$0.payload},options:[.prettyPrinted,.sortedKeys]).write(to:out)
  emit(["event":"finished","at":stopped,"count":segments.count,"frames":input.length,"sr":format.sampleRate])
 }
}
