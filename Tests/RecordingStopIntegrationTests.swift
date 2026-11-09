import AppKit

// Compiled with a test-only empty-capture seeding helper, services/hotkeys off,
// and its own temporary data root. No microphone or target application is used.
@main struct RecordingStopIntegrationTests {
    @MainActor static func main()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuStop-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        defer{try? FileManager.default.removeItem(at:root)}
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        for mode in ["typing","cancel","sleep","device"]{
            let app=AppState(),id=try app.testSeedEmptyCapture()
            app.store.preferences.keepMicWarm=false;app.microphoneStatus="录音中"
            app.finish()
            check(app.phase=="working" && app.busy,"Capture tail remains busy: "+mode)
            switch mode{
            case "typing":app.hotkeys.onStandaloneInterrupted?()
            case "cancel":app.cancel()
            case "sleep":app.sleep()
            default:app.deviceChanged()
            }
            if mode=="sleep" || mode=="device"{check(app.phase=="error","System changes flush without waiting: "+mode)}
            try? await Task.sleep(nanoseconds:260_000_000)
            let record=app.store.sessions.first{$0.id==id}!
            check(!app.busy,"Pending stop never sticks after "+mode)
            check(record.status==(mode=="cancel" ? "cancelled":"failed"),"Exactly one expected terminal state: "+mode)
            check(app.engine.ready==false,"Empty capture does not start inference: "+mode)
            check(app.microphoneStatus != "录音中","Released input never keeps a stale recording label: "+mode)
            app.shutdown()
        }
        print("Recording stop integration checks passed:",checks)
    }
}
