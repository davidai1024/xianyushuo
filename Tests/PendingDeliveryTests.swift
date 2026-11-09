import AppKit

// Runs the production awaitInput Task and store writes with fake focus, clipboard
// counters and delivery only. No microphone, external AX reads or paste events.
@main struct PendingDeliveryTests {
    @MainActor static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuPending-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        defer{try? FileManager.default.removeItem(at:root)}
        _=NSApplication.shared
        var checks=0
        func check(_ condition:Bool,_ label:String){precondition(condition,label);checks+=1}
        func wait()async{try? await Task.sleep(nanoseconds:330_000_000)}
        let app=AppState()
        let first=try app.testSeedPending()
        await wait();check(app.testDeliveryCalls==0,"No cursor never causes an automatic write")
        app.testFocusAvailable=true
        await wait();check(app.testDeliveryCalls==1,"Clicking an input after completion delivers")
        check(app.deliveryState=="verified" && app.stage=="已填入","Success UI follows actual verification receipt")
        let firstRecord=app.store.sessions.first{$0.id==first}!
        let metadata=try JSONSerialization.jsonObject(with:Data(firstRecord.metadata.utf8))as! [String:Any]
        check(metadata["initial_delivery"] != nil && metadata["late_focus_wait_seconds"] != nil,"Initial fallback and later delivery remain auditable")
        await wait();check(app.testDeliveryCalls==1,"A focused input never receives a duplicate")
        for operation in ["clipboard","new_session","cancel","sleep","shutdown","busy","disabled","manual_paste","deleted","invalid_status"]{
            app.testFocusAvailable=false;app.testResetSleep();app.store.preferences.autoPaste=true
            let id=try app.testSeedPending(),before=app.testDeliveryCalls
            switch operation {
            case "clipboard":app.testClipboardVersion+=1
            case "new_session":app.latest=UUID()
            case "cancel":app.cancel()
            case "sleep":app.sleep()
            case "shutdown":app.shutdown()
            case "busy":app.phase="working"
            case "disabled":app.store.preferences.autoPaste=false
            case "manual_paste":app.testFocusText="测试 C theft thief。"
            case "deleted":app.store.sessions.removeAll{$0.id==id};try app.store.persistSessions()
            default:var r=app.store.sessions.first{$0.id==id}!;r.status="cancelled";try app.store.update(r)
            }
            app.testFocusAvailable=true
            await wait();check(app.testDeliveryCalls==before,"Deferred delivery stops safely: "+operation)
            app.testFocusText=""
            app.testStopPending()
            app.phase="result"
        }
        // A second eligible recording replaces the first pending result.
        app.testResetSleep();app.store.preferences.autoPaste=true;app.testFocusAvailable=false
        let stale=try app.testSeedPending(),latest=try app.testSeedPending(),before=app.testDeliveryCalls
        app.testFocusAvailable=true;await wait()
        check(app.testDeliveryCalls==before+1,"Only the newest eligible result is delivered")
        check(app.store.sessions.first{$0.id==stale}!.delivery=="waiting","The replaced result is retained without a write")
        check(app.store.sessions.first{$0.id==latest}!.delivery=="verified fixture delivery","Newest result owns its receipt")
        app.shutdown()
        print("Pending delivery integration checks passed:",checks)
    }
}
