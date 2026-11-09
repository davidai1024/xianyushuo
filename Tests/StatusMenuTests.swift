import AppKit
import Foundation

/// Isolated menu model/lifecycle checks, not a substitute for physical menu clicks.
@main struct StatusMenuTests {
    @MainActor static func main()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuStatusMenuTests-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        var preferences=Preferences();preferences.keepMicWarm=false
        try AppPaths.write(preferences,to:root.appendingPathComponent("preferences.json"))
        _=NSApplication.shared
        let app=AppState.shared
        var calls:[(StatusMenuController.Action,Int,Bool)]=[]
        let controller=StatusMenuController(app:app){action,tag in calls.append((action,tag,Thread.isMainThread))}
        let menu=controller.menu
        var checks=0
        func check(_ value:Bool,_ name:String){if !value{FileHandle.standardError.write(Data("FAIL after \(checks): \(name)\n".utf8));exit(1)};checks+=1}
        func item(_ action:String)->NSMenuItem{menu.items.first{ $0.identifier?.rawValue==action }!}
        let original=menu.items.map(ObjectIdentifier.init),header=menu.items.first!.view!
        let initialWidth=menu.size.width
        check(menu.minimumWidth==StatusMenuPlacement.minimumWidth,"Popup has a fixed minimum layout width before presentation")
        check(controller.status.menu==nil && controller.status.button?.target === controller,"Status button uses explicit main-queue activation, no automatic menu export")
        check(menu.delegate==nil,"No synchronous Swift delegate/population during tracking")
        check(header is StatusMenuHeader,"Header uses one native view tree")
        check(item("toggleRecording").isEnabled && !item("translate").isHidden,"Idle dictation/translation available")
        check(item("cancelTask").isHidden && item("quit").isEnabled,"Idle hides cancel and permits quit")
        check(!item("copyLast").isEnabled,"No fabricated recent result")
        for index in 0..<5_000 {
            app.phase=index%4==0 ? "recording":index%4==1 ? "working":"idle"
            app.stage="状态 \(index%4)";app.store.preferences.cleanup=CleanupMode.allCases[index%3]
            controller.refresh();menu.update()
            check(menu.items.map(ObjectIdentifier.init)==original && menu.items.first!.view === header,"Repeated updates never replace menu/header objects")
            if index%1000==0{check(menu.size.width==initialWidth,"Closed-menu state changes cannot grow the popup width")}
        }
        app.phase="recording";controller.refresh()
        check(item("toggleRecording").title=="结束听写" && item("toggleRecording").isEnabled,"Recording can stop from menu")
        check(!item("translate").isEnabled && !item("quit").isEnabled && !item("cancelTask").isHidden,"Busy actions guarded")
        app.phase="working";controller.refresh();check(!item("toggleRecording").isEnabled,"Processing cannot start another capture")
        var record=SessionRecord();record.raw="已保存的原文";app.store.sessions=[record]
        app.phase="idle";controller.refresh();check(item("copyLast").isEnabled,"Saved raw result remains recoverable")
        record.raw="";record.output="已保存的结果";app.store.sessions=[record];controller.refresh()
        check(item("copyLast").isEnabled,"Saved final result remains recoverable")
        let levels=menu.items.first{$0.title=="整理程度"}!.submenu!
        check(levels.items.count==3,"All three cleanup modes retained")
        app.store.preferences.cleanup = .structured;controller.refresh()
        check(levels.items.map(\.state)==[.off,.off,.on],"Cleanup selection follows app state")
        for (index,mode) in ["system","light","dark"].enumerated(){
            UserDefaults.standard.set(mode,forKey:DianyuDesign.appearanceKey);controller.refresh()
            let themes=menu.items.first{$0.title=="外观"}!.submenu!
            check(themes.items[index].state == .on && themes.items.filter{$0.state == .on}.count==1,"Appearance has exactly one selection")
            if mode != "system"{
                let expected:NSAppearance.Name=mode=="dark" ? .darkAqua:.aqua
                check(menu.appearance?.bestMatch(from:[.darkAqua,.aqua])==expected,"Popup explicitly follows chosen theme")
                check(levels.appearance?.bestMatch(from:[.darkAqua,.aqua])==expected,"Submenus follow the same theme")
                check(header.appearance?.bestMatch(from:[.darkAqua,.aqua])==expected,"Header never falls back to a light hosting process")
            }
        }
        for entry in menu.items where entry.action != nil && entry.submenu==nil{check(entry.target === controller,"Stable action target retained")}
        UserDefaults.standard.set("light",forKey:DianyuDesign.appearanceKey)
        NotificationCenter.default.post(name:UserDefaults.didChangeNotification,object:nil)
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(menu.items.first{$0.title=="外观"}!.submenu!.items[1].state == .on,"Appearance changed in settings updates menu without opening/rebuilding")
        app.phase="working"
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(!item("quit").isEnabled,"Observable refresh reads post-publication state")
        app.phase="idle";controller.refresh()
        for name in ["toggleRecording","translate","copyLast","showWindow","openPage"]{
            controller.performAction(item(name))
        }
        let foreign=NSMenuItem(title:"foreign",action:nil,keyEquivalent:"");foreign.identifier=NSUserInterfaceItemIdentifier("quit");controller.performAction(foreign)
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(calls.count==5 && calls.allSatisfy{$0.2},"Owned actions route on main thread; foreign sender ignored")
        app.phase="working";controller.refresh();controller.performAction(item("toggleRecording"));controller.performAction(item("quit"))
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(calls.count==5,"Disabled actions cannot bypass busy guard through accessibility")
        controller.performAction(item("showWindow"))
        RunLoop.current.run(mode:.eventTracking,before:Date().addingTimeInterval(0.01))
        check(calls.count==5,"Menu actions cannot execute inside event-tracking mode")
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(calls.count==6,"Menu action executes after returning to default mode")
        for _ in 0..<1_000{RuntimeDiagnostics.event("test_event")}
        let log=root.appendingPathComponent("lifecycle.jsonl"),bytes=try Data(contentsOf:log)
        check(bytes.count<=65_536,"Diagnostics bounded")
        for line in String(decoding:bytes,as:UTF8.self).split(separator:"\n"){_=try JSONSerialization.jsonObject(with:Data(line.utf8))}
        check((try FileManager.default.attributesOfItem(atPath:log.path)[.posixPermissions]as?NSNumber)?.intValue==0o600,"Diagnostics private")
        check(!String(decoding:bytes,as:UTF8.self).contains(record.output),"Diagnostics omit transcript")
        controller.invalidate();app.shutdown()
        print("Status menu checks passed:",checks,"including 5000 stable-tree refreshes")
    }
}
