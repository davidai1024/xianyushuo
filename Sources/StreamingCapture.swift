import Foundation
import AVFoundation

struct CapturedSegment {
    let owner:String,index:Int,url:URL,startFrame:Int64,frameCount:Int64,sampleRate:Double
    var payload:[String:Any]{["recording_id":owner,"audio":url.path,"start_frame":startFrame,"frame_count":frameCount,"sample_rate":sampleRate]}
}

/// A second, temporary copy of the original PCM. Cuts never remove or overlap samples.
/// Only long recordings with an actual quiet pause are split; other input stays whole.
final class StreamingCapture {
    static let root=AppPaths.root.appendingPathComponent("Streaming",isDirectory:true)
    private let owner:String,format:AVAudioFormat,directory:URL
    private var writer:AVAudioFile?
    private var cursor:Int64=0,start:Int64=0
    private var quiet=0.0,peakRMS=0.0
    private var published=0
    private var failed=false
    private(set) var failureReason=""
    private(set) var segments:[CapturedSegment]=[]
    var onSegment:((CapturedSegment)->Void)?
    init(owner:String,format:AVAudioFormat)throws{
        self.owner=owner;self.format=format;directory=Self.root.appendingPathComponent(owner,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try open()
    }
    private func open()throws{
        writer=try AVAudioFile(forWriting:directory.appendingPathComponent("\(segments.count).wav"),settings:format.settings,commonFormat:format.commonFormat,interleaved:format.isInterleaved)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:directory.appendingPathComponent("\(segments.count).wav").path)
    }
    func append(_ buffer:AVAudioPCMBuffer){
        guard !failed else{return}
        do{
            try writer?.write(from:buffer);cursor+=Int64(buffer.frameLength)
            guard let samples=buffer.floatChannelData?[0],buffer.frameLength>0 else{return}
            var sum=0.0
            for i in 0..<Int(buffer.frameLength){sum+=Double(samples[i])*Double(samples[i])}
            let rms=sqrt(sum/Double(buffer.frameLength)),seconds=Double(buffer.frameLength)/format.sampleRate
            peakRMS=max(peakRMS,rms)
            // Follow quiet speakers: never use a fixed normal-voice threshold.
            let threshold=max(0.00003,min(0.002,peakRMS*0.035))
            quiet=rms<threshold ? quiet+seconds:0
            // A cut is provisional until at least 1.2s follows it. If recording
            // ends in that quiet tail, merge it before any decoder sees it.
            if published<segments.count && Double(cursor-start)/format.sampleRate>=1.2{
                onSegment?(segments[published]);published+=1
            }
            if Double(cursor-start)/format.sampleRate>=12 && quiet>=0.4{
                seal();try open();quiet=0
            }
        }catch{failed=true;failureReason="segment_write_failed";writer=nil}
    }
    private func seal(){
        writer=nil
        guard cursor>start else{return}
        let segment=CapturedSegment(owner:owner,index:segments.count,url:directory.appendingPathComponent("\(segments.count).wav"),startFrame:start,frameCount:cursor-start,sampleRate:format.sampleRate)
        segments.append(segment);start=cursor
    }
    func finish()->[CapturedSegment]{
        writer=nil
        guard !failed,!segments.isEmpty else{return []}
        let tail=Double(cursor-start)/format.sampleRate
        if published<segments.count && tail<1.2 && cursor>start{
            // The pending chunk was never published, so it can safely absorb its
            // too-short tail. Reuse remains gated by exact original PCM hashes.
            let previous=segments.removeLast()
            if segments.isEmpty{return []} // Nothing has run: decode original once.
            let pending=directory.appendingPathComponent("\(previous.index).wav")
            let tailURL=directory.appendingPathComponent("\(previous.index+1).wav")
            let merged=directory.appendingPathComponent("merged-\(previous.index).wav")
            do{
                let output=try AVAudioFile(forWriting:merged,settings:format.settings,commonFormat:format.commonFormat,interleaved:format.isInterleaved)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:merged.path)
                for url in [pending,tailURL]{
                    let input=try AVAudioFile(forReading:url)
                    guard let buffer=AVAudioPCMBuffer(pcmFormat:input.processingFormat,frameCapacity:4096)else{throw AppError.message("分段缓冲不可用。")}
                    while input.framePosition<input.length{
                        try input.read(into:buffer);if buffer.frameLength==0{break};try output.write(from:buffer)
                    }
                }
                segments.append(CapturedSegment(owner:owner,index:previous.index,url:merged,startFrame:previous.startFrame,frameCount:cursor-previous.startFrame,sampleRate:format.sampleRate))
            }catch{failureReason="short_tail_merge_failed";return []}
        }else{seal()}
        return segments
    }
    static func remove(_ owner:String){
        guard UUID(uuidString:owner) != nil else{return}
        try? FileManager.default.removeItem(at:root.appendingPathComponent(owner,isDirectory:true))
    }
}
