import AppKit

/// Controlled native UI/state integration; no microphone or external editor.
@main struct OverlayCompletionTests {
    @MainActor static func main()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuOverlay-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        defer{try? FileManager.default.removeItem(at:root)}
        _=NSApplication.shared
        let beforeWindows=Set(NSApp.windows.map(ObjectIdentifier.init))
        let app=AppState(),overlay=OverlayController(app:app)
        app.overlay=overlay
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        check(NSApp.windows.filter{!beforeWindows.contains(ObjectIdentifier($0))}.count==1,"Exactly one capsule window is created")
        func wait(_ seconds:Double)async{try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))}
        let input=NSTextField(string:""),text="capsule completion fixture"
        app.latest=UUID();app.phase="working";app.stage="正在完成";app.deliveryState="verified"
        overlay.show();await wait(0.32)
        check(overlay.panel.isVisible,"Active finalization cannot inherit an old success timeout")
        check(input.stringValue.isEmpty,"No text has been inserted during the simulated editor delay")
        // This deliberately delays the native value change beyond the success
        // hold. A timer started before actual delivery would fail the test above.
        input.stringValue=text;let inserted=ProcessInfo.processInfo.systemUptime
        var probe=DeliveryReadbackProbe()
        check(!probe.observe(input.stringValue,before:"",inserted:text,expected:text,webPaste:false),"One value observation is insufficient")
        await wait(0.035)
        check(probe.observe(input.stringValue,before:"",inserted:text,expected:text,webPaste:false),"The native value is present before success is displayed")
        let confirmed=ProcessInfo.processInfo.systemUptime
        app.phase="result";app.stage="已填入";app.deliveryState="verified";overlay.show()
        await wait(0.11)
        check(overlay.panel.isVisible,"Success feedback remains briefly visible after confirmed text")
        await wait(0.21)
        check(!overlay.panel.isVisible,"The single capsule disappears after the 250ms hold")
        let hidden=ProcessInfo.processInfo.systemUptime
        check(hidden>confirmed && confirmed>inserted,"Native value then confirmation then disappearance have strict order")
        let journal=try String(contentsOf:root.appendingPathComponent("lifecycle.jsonl"))
        let events=journal.split(separator:"\n").compactMap{try? JSONSerialization.jsonObject(with:Data($0.utf8))as?[String:Any]}
        let auto=events.last{$0["event"]as?String=="overlay_auto_hidden"}!
        let observedHold=(auto["uptime"]as!Double)-confirmed
        check(observedHold>=0.25 && observedHold<0.65,"The real auto-hide timer is measured after confirmation")
        print("Controlled native confirmation-to-hide milliseconds:",Int(observedHold*1000))

        app.latest=UUID();app.phase="result";app.deliveryState="verified";overlay.show()
        await wait(0.05);app.latest=UUID();app.phase="working";app.stage="正在完成"
        await wait(0.28)
        check(overlay.panel.isVisible,"A stale timer cannot hide a new busy job even without another show call")
        app.phase="result";app.deliveryState="verified";overlay.show()
        await wait(0.05);app.latest=UUID()
        await wait(0.28)
        check(overlay.panel.isVisible,"A stale timer cannot hide another session with the same result state")
        app.phase="result";app.deliveryState="verified";overlay.show()
        await wait(0.05);app.deliveryState="unverified"
        await wait(0.28)
        check(overlay.panel.isVisible,"Changed delivery evidence invalidates a pending success timeout")
        overlay.show();await wait(0.3)
        check(overlay.panel.isVisible,"An unverified write has no automatic success dismissal")
        app.phase="error";app.deliveryState="verified";overlay.show();await wait(0.3)
        check(overlay.panel.isVisible,"Errors override stale successful delivery")
        app.phase="result";app.deliveryState="verified";overlay.show()
        await wait(0.05);overlay.setExpanded(true);await wait(0.28)
        check(overlay.panel.isVisible && app.overlayExpanded,"User-expanded details cannot be hidden by the old timeout")
        overlay.show();await wait(0.05)
        app.phase="recording";app.latest=UUID();overlay.show();await wait(0.28)
        check(overlay.panel.isVisible,"Starting a recording replaces the previous dismissal task")
        app.phase="working";app.stage="正在完成"
        let before=CapsuleMotionState.resolve(phase:app.phase,stage:app.stage,delivery:app.deliveryState)
        app.stage=OverlayLayout.processingTitle("正在填入")
        check(before==CapsuleMotionState.resolve(phase:app.phase,stage:app.stage,delivery:app.deliveryState),"Cleanup-to-paste keeps one visible state and light animation")
        overlay.hide();check(!overlay.panel.isVisible,"Manual hiding closes the single window")
        app.overlay=nil;app.phase="idle";app.shutdown()
        print("Overlay completion integration checks passed:",checks)
    }
}
