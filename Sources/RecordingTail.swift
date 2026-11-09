import Foundation

enum RecordingTail {
    /// AVAudioEngine's requested tap size is advisory. A real 100 ms tap can
    /// still contain the last syllable when the stop key arrives.
    static func seconds(bufferFrames:Int,sampleRate:Double)->Double{
        guard sampleRate.isFinite,sampleRate>0,bufferFrames>0 else{return 0.12}
        return min(0.22,max(0.12,2*Double(bufferFrames)/sampleRate))
    }
}

/// Separate from the shortcut-start token: typing immediately after stopping
/// must not invalidate the recording's pending completion.
@MainActor final class RecordingStopController {
    private var generation=0
    private var task:Task<Void,Never>?
    private(set) var pending=false
    func request(after seconds:Double,complete:@escaping @MainActor ()->Void){
        cancel();pending=true;let ticket=generation
        guard seconds>0 else{pending=false;complete();return}
        task=Task{[weak self]in
            do{try await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}catch{return}
            guard let self,self.generation==ticket else{return}
            self.pending=false;self.task=nil;complete()
        }
    }
    func cancel(){generation+=1;task?.cancel();task=nil;pending=false}
    deinit{task?.cancel()}
}
