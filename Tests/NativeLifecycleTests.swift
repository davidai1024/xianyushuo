import AppKit
import SwiftUI

@main struct NativeLifecycleTests {
    @MainActor static func main()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuLifecycle-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        defer{try? FileManager.default.removeItem(at:root)}
        _=NSApplication.shared
        let app=AppState.shared
        var checks=0
        func check(_ condition:Bool,_ name:String){precondition(condition,name);checks+=1}
        let deferred=DefaultModeAction();var activated=0
        deferred.request{activated+=1};deferred.request{activated+=100}
        check(deferred.pending && activated==0,"Activation requests coalesce without synchronous UI calls")
        RunLoop.current.run(mode:.eventTracking,before:Date().addingTimeInterval(0.01))
        check(activated==0 && deferred.pending,"Menu tracking cannot run pending window activation")
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(activated==1 && !deferred.pending,"Default run-loop mode executes exactly one activation")
        deferred.request{activated+=1};deferred.cancel()
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(activated==1 && !deferred.pending,"Termination cancels a pending window activation")
        let applicationMenu=ApplicationMenuController(app:app)
        let tree=applicationMenu.menu.items.map(ObjectIdentifier.init)
        check(NSApp.mainMenu === applicationMenu.menu,"Main menu explicitly owned by native controller")
        check(applicationMenu.menu.items.map(\.title)==["咸鱼说","文件","编辑","显示","窗口","帮助"],"Core native menu groups retained")
        let appMenu=applicationMenu.menu.items[0].submenu!
        check(appMenu.items.first{$0.keyEquivalent==","}?.title=="设置…","Settings shortcut retained")
        check(appMenu.items.first{$0.keyEquivalent=="q"}?.action==#selector(NSApplication.terminate(_:)),"Quit keeps application termination guard")
        check(NSApp.servicesMenu != nil && NSApp.windowsMenu != nil && NSApp.helpMenu != nil,"AppKit standard menu integration retained")
        let edit=applicationMenu.menu.items[2].submenu!
        for (key,action)in [("z","undo:"),("x","cut:"),("c","copy:"),("v","paste:"),("a","selectAll:")]{
            check(edit.items.contains{$0.keyEquivalent==key && $0.action==Selector(action) && $0.target==nil},"Responder-chain editing "+action)
        }
        let window=AppDelegate.makeMainWindow(app:app)
        AppDelegate.mainWindow=window
        let host=window.contentView!
        check(window.identifier?.rawValue=="main","Stable accessibility window identifier")
        check(!window.isReleasedWhenClosed,"Closing retains main window")
        check(window.frame.width==1040 && window.frame.height==740,"Compact outer window dimensions")
        check(window.minSize==NSSize(width:920,height:640),"Minimum dimensions retained")
        check(window.titleVisibility == .hidden && window.titlebarAppearsTransparent,"Existing custom window chrome retained")
        check(window.styleMask.contains(.fullSizeContentView) && window.styleMask.contains(.resizable),"Hosting fills resizable window")
        for i in 0..<100{
            app.page=["输入","历史","个人词表","统计","设置","录音","快捷键","权限","模型资源","关于"][i%10]
            window.close()
            RunLoop.current.run(until:Date().addingTimeInterval(0.001))
            check(AppDelegate.mainWindow === window && window.contentView === host,"Window and hosting view identity survive close/page updates")
            check(NSApp.mainMenu === applicationMenu.menu && applicationMenu.menu.items.map(ObjectIdentifier.init)==tree,"View updates do not rebuild application menu")
        }
        var opened=0;app.showMain={opened+=1}
        let settings=appMenu.items.first{$0.keyEquivalent==","}!
        check(NSApp.sendAction(settings.action!,to:settings.target,from:settings),"Native settings action routed")
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(app.page=="设置" && opened==1,"Settings uses deferred main-queue routing")
        let help=NSApp.helpMenu!.items.first{$0.title=="关于与本地隐私"}!
        check(NSApp.sendAction(help.action!,to:help.target,from:help),"Native about action routed")
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(app.page=="关于" && opened==2,"About uses same retained window route")
        var guided=0;app.showOnboarding={guided+=1}
        let guide=NSApp.helpMenu!.items.first{$0.title=="使用引导…"}!
        check(NSApp.sendAction(guide.action!,to:guide.target,from:guide),"Native onboarding entry routed")
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(guided==1 && app.onboarding.visible,"Onboarding uses default-mode action bridge")
        app.onboarding.deferSetup()
        let first=VocabularyEntry(word:"Muse");try app.store.saveVocabulary([first])
        check(LibraryStore().vocabulary==[first],"Vocabulary persists independently of SwiftUI scene ownership")
        app.shutdown();AppDelegate.mainWindow=nil;window.orderOut(nil)
        print("Native lifecycle checks passed:",checks)
    }
}
