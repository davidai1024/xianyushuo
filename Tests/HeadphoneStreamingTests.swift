import Foundation
import AVFoundation

@main struct HeadphoneStreamingTests {
    static func main()throws{
        var checks=0
        func check(_ value:Bool,_ name:String){if !value{FileHandle.standardError.write(Data("FAIL: \(name) after \(checks) checks\n".utf8));exit(1)};checks+=1}
        for warm in [false,true]{for protect in [false,true]{for bt in [false,true]{check(MicWarmPolicy.allows(requested:warm,protectControls:protect,bluetooth:bt)==(warm && (!protect || !bt)),"Headphone/warm preference combination")}}}
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuHeadphoneTests-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);defer{try? FileManager.default.removeItem(at:root)}
        let format=AVAudioFormat(standardFormatWithSampleRate:16000,channels:1)!
        // Native PCM tests include speech-shaped buffers, digital pauses and late stops.
        func run(_ spans:[(Double,Bool)])throws->([CapturedSegment],[CapturedSegment],[Float]){
            let owner=UUID().uuidString,capture=try StreamingCapture(owner:owner,format:format)
            var published:[CapturedSegment]=[],all:[Float]=[]
            capture.onSegment={published.append($0)}
            for (duration,speech) in spans{
                var remaining=Int(duration*16000)
                while remaining>0{
                    let n=min(1024,remaining),buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)!
                    buffer.frameLength=AVAudioFrameCount(n)
                    for i in 0..<n{let v:Float=speech ? Float(sin(Double(all.count+i)*0.13)*0.04):0;buffer.floatChannelData![0][i]=v}
                    all.append(contentsOf:UnsafeBufferPointer(start:buffer.floatChannelData![0],count:n));capture.append(buffer);remaining-=n
                }
            }
            let done=capture.finish();return(done,published,all)
        }
        func verify(_ parts:[CapturedSegment],_ pcm:[Float])throws{
            var rebuilt:[Float]=[]
            for (index,part) in parts.enumerated(){
                check(part.index==index && part.startFrame==Int64(rebuilt.count),"Sequential exact PCM coverage")
                let input=try AVAudioFile(forReading:part.url),buffer=AVAudioPCMBuffer(pcmFormat:input.processingFormat,frameCapacity:4096)!
                let before=rebuilt.count
                while input.framePosition<input.length{
                    try input.read(into:buffer);if buffer.frameLength==0{break}
                    rebuilt.append(contentsOf:UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))
                }
                check(Int64(rebuilt.count-before)==part.frameCount,"Native file metadata matches frames")
            }
            check(rebuilt==pcm,"No missing duplicated or altered native samples")
        }
        let short=try run([(4,true),(0.8,false)]);check(short.0.isEmpty && short.1.isEmpty,"Short utterance never waits for background chunks")
        let late=try run([(12.1,true),(0.6,false)]);check(late.0.isEmpty && late.1.isEmpty,"Late first cut processes original once, no tiny tail decode")
        let flowing=try run([(12.1,true),(0.5,false),(5,true)]);check(flowing.0.count==2 && flowing.1.count==1,"Useful prefix published while speaking");try verify(flowing.0,flowing.2)
        let merged=try run([(12.1,true),(0.5,false),(12.2,true),(0.6,false)]);check(merged.0.count==2 && merged.1.count==1,"Unpublished last chunk absorbs short tail");try verify(merged.0,merged.2)
        let long=try run([(12.1,true),(0.5,false),(12.2,true),(0.5,false),(3,true)]);check(long.0.count==3 && long.1.count==2,"Several useful background chunks retained");try verify(long.0,long.2)
        print("Headphone/stream PCM checks passed:",checks)
    }
}
