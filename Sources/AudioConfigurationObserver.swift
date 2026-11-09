import AVFoundation

/// The engine posts synchronously on its own serial queue. Never deliver the
/// NotificationCenter block through OperationQueue.main: engine destruction on
/// main can wait for that very queue. Only the actor callback is asynchronous.
final class AudioConfigurationObserver {
    private var token:NSObjectProtocol?
    init(engine:AVAudioEngine,_ callback:@escaping @MainActor @Sendable ()->Void){
        token=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:nil){[weak self] _ in
            // Teardown can post while the sender is deallocating. Only the
            // observer's lifetime crosses the queue boundary.
            Task{@MainActor in
                guard self != nil else{return}
                callback()
            }
        }
    }
    deinit{if let token{NotificationCenter.default.removeObserver(token)}}
}
