import Foundation

/// DispatchQueue.main can execute inside AppKit's nested menu tracking loop.
/// Window activation waits for the default run-loop mode instead.
@MainActor final class DefaultModeAction {
    private(set) var pending=false
    private var generation=0
    func request(_ action:@escaping @MainActor ()->Void){
        guard !pending else{return}
        pending=true;generation+=1;let ticket=generation
        Self.enqueue{[weak self]in
            guard let self,self.generation==ticket else{return}
            self.pending=false;action()
        }
    }
    func cancel(){generation+=1;pending=false}
    nonisolated static func enqueue(_ action:@escaping @MainActor ()->Void){
        RunLoop.main.perform(inModes:[.default]){MainActor.assumeIsolated{action()}}
    }
}
