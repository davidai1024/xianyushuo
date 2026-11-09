import AVFoundation

/// The engine posts synchronously on its own serial queue. Never deliver the
/// NotificationCenter block through OperationQueue.main: engine destruction on
/// main can wait for that very queue. Only the actor callback is asynchronous.
final class AudioConfigurationObserver {
    private var token:NSObjectProtocol?
    init(_ callback:@escaping @MainActor @Sendable (ObjectIdentifier)->Void){
        token=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:nil,queue:nil){note in
            guard let engine=note.object as?AVAudioEngine else{return}
            // Do not retain the AVAudioEngine/Notification across this hop.
            Task{@MainActor [weak engine]in
                guard let engine else{return}
                callback(ObjectIdentifier(engine))
            }
        }
    }
    deinit{if let token{NotificationCenter.default.removeObserver(token)}}
}
