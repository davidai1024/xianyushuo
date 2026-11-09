import Foundation
import Darwin

@main struct AudioRestoreGuard {
    static func main(){
        guard CommandLine.arguments.count==4,let parent=Int32(CommandLine.arguments[3])else{return}
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),owner=CommandLine.arguments[2]
        let url=root.appendingPathComponent("recording-mute-recovery.json")
        // No event posting, microphone, UI, network, or additional permissions.
        while kill(parent,0)==0{
            guard let data=try? Data(contentsOf:url),let lease=try? JSONDecoder().decode(OutputMuteJournal.self,from:data),lease.owner==owner,!lease.entries.isEmpty else{return}
            Thread.sleep(forTimeInterval:0.2)
        }
        for _ in 0..<50{
            if RecordingMuteController.recover(root:root,owner:owner){return}
            Thread.sleep(forTimeInterval:0.2)
        }
    }
}
