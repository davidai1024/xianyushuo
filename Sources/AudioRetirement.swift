import Foundation

/// Owns only engines already detached from capture. Hardware teardown may wait
/// for Bluetooth/CoreAudio; recognition can proceed from the closed WAV meanwhile.
final class AudioRetirement:@unchecked Sendable {
    private let queue=DispatchQueue(label:"im.muse.dianyu.audio-retirement",qos:.userInitiated)
    private let lock=NSLock()
    private var count=0
    var pending:Bool{lock.withLock{count>0}}
    func submit(_ release:@escaping()->Void,finished:(()->Void)?=nil){
        lock.withLock{count+=1}
        queue.async{[self]in release();lock.withLock{count-=1};if let finished{DispatchQueue.main.async(execute:finished)}}
    }
    func wait()async{
        while pending{await withCheckedContinuation{continuation in queue.async{continuation.resume()}}}
    }
}
