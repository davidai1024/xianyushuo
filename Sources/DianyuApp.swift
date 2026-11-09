import SwiftUI
import AppKit

@_cdecl("DianyuRunApplication")
func DianyuRunApplication(){
    dispatchPrecondition(condition:.onQueue(.main))
    MainActor.assumeIsolated {
        let application=NSApplication.shared
        let preferences=(try? Data(contentsOf:AppPaths.root.appendingPathComponent("preferences.json"))).flatMap{try? JSONDecoder().decode(Preferences.self,from:$0)}
        application.setActivationPolicy(preferences?.hideDockIcon == true ? .accessory:.regular)
        let delegate=AppDelegate()
        application.delegate=delegate
        withExtendedLifetime(delegate){application.run()}
    }
}
@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    // This is a single-window utility: closing hides it while the menu stays alive.
    // Keep the window/hosting tree alive until normal process termination.
    static var mainWindow:NSWindow?
    private var setupWindow:SetupWindowController?
    private var statusMenu:StatusMenuController?
    private var applicationMenu:ApplicationMenuController?
    private let activation=DefaultModeAction()
    private let presenceAction=DefaultModeAction()
    private var closeObserver:NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification:Notification){
        if let icon=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap({NSImage(contentsOf:$0)}){NSApp.applicationIconImage=icon}
        let existing=NSRunningApplication.runningApplications(withBundleIdentifier:Bundle.main.bundleIdentifier ?? "im.muse.dianyu").filter{$0.processIdentifier != getpid()}
        if let existing=existing.first {existing.activate(options:[.activateIgnoringOtherApps]);NSApp.terminate(nil);return}
        let app=AppState.shared;app.overlay=OverlayController(app:app);app.showMain={ [weak self] in self?.showWindow() }
        app.showOnboarding={ [weak self]in self?.showSetup() }
        app.updateDockVisibility={ [weak self] hidden in self?.applyDockVisibility(hidden) }
        applyDockVisibility(app.store.preferences.hideDockIcon)
        RuntimeDiagnostics.event("launch")
        applicationMenu=ApplicationMenuController(app:app)
        Self.mainWindow=Self.makeMainWindow(app:app)
        closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:nil,queue:.main){notification in
            guard let window=notification.object as?NSWindow else{return}
            DispatchQueue.main.async {
                guard window === Self.mainWindow else{return}
                RuntimeDiagnostics.event("window_close")
                if app.phase=="preparing"{app.cancel()}else if app.phase=="recording"{app.finish()}
            }
        }
        statusMenu=StatusMenuController(app:app){[weak self] action,tag in
            guard let self else{return}
            // Swift-to-Swift calls after the main-queue bridge; AppKit never enters
            // an actor-isolated Objective-C action thunk for the status menu.
            switch action {
            case .toggleRecording:self.toggleRecording()
            case .translate:self.translate()
            case .cancelTask:self.cancelTask()
            case .copyLast:self.copyLast()
            case .showWindow:self.showWindow()
            case .hideWindow:Self.mainWindow?.orderOut(nil);self.setupWindow?.window.orderOut(nil)
            case .quit:self.quit()
            case .changeCleanup:let item=NSMenuItem();item.tag=tag;self.changeCleanup(item)
            case .changeAppearance:let item=NSMenuItem();item.tag=tag;self.changeAppearance(item)
            case .openPage:let item=NSMenuItem();item.tag=tag;self.openPage(item)
            }
        }
        app.startServices()
        // Finish the launch callback before activating/exporting the menus.
        if app.onboarding.shouldPresentAutomatically{app.onboarding.present();showSetup()}else{showWindow()}
    }
    static func makeMainWindow(app:AppState)->NSWindow {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1040,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.identifier=NSUserInterfaceItemIdentifier("main");window.title="咸鱼说"
        window.isReleasedWhenClosed=false;window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true
        window.toolbar=nil;window.isMovableByWindowBackground=true;window.minSize=NSSize(width:920,height:640)
        let host=ClearHostingView(rootView:RootView(app:app));host.sizingOptions=[]
        host.autoresizingMask=[.width,.height];window.contentView=host
        let area=(NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:960))
        window.setFrame(NSRect(x:0,y:0,width:min(1040,area.width-40),height:min(740,area.height-40)),display:false)
        window.setFrameAutosaveName("DianyuMainWindow")
        if !window.setFrameUsingName("DianyuMainWindow"){window.center()}
        UserDefaults.standard.set(4,forKey:"dianyu.designLayoutVersion")
        RuntimeDiagnostics.event("native_window_created")
        return window
    }
    private func applyDockVisibility(_ requested:Bool){
        presenceAction.request{
            let hidden=AppState.shared.store.preferences.hideDockIcon
            let policy:NSApplication.ActivationPolicy=hidden ? .accessory:.regular
            guard NSApp.activationPolicy() != policy else{return}
            let wasKey=Self.mainWindow?.isKeyWindow == true
            NSApp.setActivationPolicy(policy)
            if wasKey{Self.mainWindow?.makeKeyAndOrderFront(nil);if !hidden{NSApp.activate(ignoringOtherApps:true)}}
            RuntimeDiagnostics.event("dock_presence",field:hidden ? "accessory":"regular")
        }
    }
    private func showSetup(){
        if setupWindow==nil{setupWindow=SetupWindowController(app:AppState.shared){[weak self]in self?.showWindow()}}
        Self.mainWindow?.orderOut(nil);setupWindow?.show();applyDockVisibility(AppState.shared.store.preferences.hideDockIcon)
    }
    @objc func showWindow(){
        if AppState.shared.onboarding.visible{showSetup();return}
        activation.request{[weak self]in
            guard let self,let window=Self.mainWindow else{return}
            RuntimeDiagnostics.event("show_window")
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            self.applyDockVisibility(AppState.shared.store.preferences.hideDockIcon)
        }
    }
    @objc func toggleRecording(){let app=AppState.shared;if app.capturing{app.finish()}else{app.begin()}}
    @objc func translate(){AppState.shared.begin(translate:true)}
    @objc func copyLast(){if let result=AppState.shared.latestRecord{Delivery.copy(result.output.isEmpty ? result.raw:result.output)}}
    @objc func cancelTask(){AppState.shared.cancel()}
    @objc func changeCleanup(_ sender:NSMenuItem){guard !AppState.shared.busy else{return};guard CleanupMode.allCases.indices.contains(sender.tag) else{return};AppState.shared.store.preferences.cleanup=CleanupMode.allCases[sender.tag];AppState.shared.applyPreferences()}
    @objc func changeAppearance(_ sender:NSMenuItem){let values=["system","light","dark"];guard values.indices.contains(sender.tag) else{return};UserDefaults.standard.set(values[sender.tag],forKey:DianyuDesign.appearanceKey);DianyuDesign.applyAppearance();statusMenu?.refresh()}
    @objc func openPage(_ sender:NSMenuItem){let pages=["输入","历史","个人词表","统计","设置"];guard pages.indices.contains(sender.tag) else{return};RuntimeDiagnostics.event("menu_page",field:pages[sender.tag]);AppState.shared.page=pages[sender.tag];showWindow()}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool{showWindow();return true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if AppState.shared.busy {AppState.shared.notice="请先结束或取消当前任务，再退出或安装更新。";showWindow();return .terminateCancel}
        AppState.shared.shutdown();AudioReplay.shared.stop();return .terminateNow
    }
    func applicationWillTerminate(_ notification:Notification){RuntimeDiagnostics.event("clean_exit");activation.cancel();presenceAction.cancel();statusMenu?.invalidate();statusMenu=nil;applicationMenu=nil;if let closeObserver{NotificationCenter.default.removeObserver(closeObserver)};AppState.shared.shutdown()}
}
