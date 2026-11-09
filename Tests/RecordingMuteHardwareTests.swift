import Foundation
import Darwin

/// Briefly tests the currently selected output; no playback, mic, or UI.
@main struct RecordingMuteHardwareTests {
    static func main()throws{
        let audio=CoreOutputAudio()
        guard let uid=audio.defaultUID(),!audio.controls(uid).isEmpty else{print("Current output has no supported mute/volume control");exit(2)}
        let candidates=audio.controls(uid)+audio.volumeControls(uid)
        var controls:[OutputControl]=[]
        for c in candidates where !controls.contains(where:{$0.kind==c.kind && $0.channel==c.channel}){controls.append(c)}
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        if CommandLine.arguments.count>2,CommandLine.arguments[2]=="verify"{
            let saved=try JSONDecoder().decode([OutputControl].self,from:Data(contentsOf:root.appendingPathComponent("hardware-before.json")))
            guard saved.allSatisfy({c in audio.read(c).map{abs($0-c.original)<0.0001} ?? false})else{exit(3)}
            print("Output state matches the pre-crash hardware snapshot");return
        }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        try JSONEncoder().encode(controls).write(to:root.appendingPathComponent("hardware-before.json"),options:.atomic)
        let controller=RecordingMuteController(root:root,observe:false)
        let old=controls.map{audio.read($0)}
        defer{
            controller.end()
            // Independent safety rollback only for a still-owned silent value;
            // preserve a different volume the user explicitly chose meanwhile.
            for c in controls{if let current=audio.read(c),abs(current-c.muted)<0.0001,abs(current-c.original)>0.0001{_ = audio.write(c,c.original)}}
        }
        guard controller.begin(enabled:true,watchdog:false)else{throw AppError.message("Mute not confirmed")}
        precondition(audio.controls(uid).allSatisfy{c in audio.read(c).map{abs($0-c.muted)<0.0001} ?? false})
        if CommandLine.arguments.count>3,CommandLine.arguments[2]=="crash"{
            let journal=try JSONDecoder().decode(OutputMuteJournal.self,from:Data(contentsOf:root.appendingPathComponent("recording-mute-recovery.json")))
            let guardProcess=Process();guardProcess.executableURL=URL(fileURLWithPath:CommandLine.arguments[3]);guardProcess.arguments=[root.path,journal.owner,String(getpid())]
            try guardProcess.run();Thread.sleep(forTimeInterval:0.15);Darwin._exit(0)
        }
        Thread.sleep(forTimeInterval:0.15);controller.end()
        RunLoop.current.run(until:Date().addingTimeInterval(1.7))
        precondition(zip(controls,old).allSatisfy{c,v in guard let v,let now=audio.read(c)else{return false};return abs(v-now)<0.0001})
        print("Current output hardware mute, scalar-volume and settled restoration passed")
    }
}
