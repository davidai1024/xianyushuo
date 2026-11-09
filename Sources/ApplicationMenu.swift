import AppKit

/// A stable application menu, independent of SwiftUI scene/command rebuilding.
@MainActor final class ApplicationMenuController:NSObject {
    let menu=NSMenu()
    private let app:AppState
    init(app:AppState){
        self.app=app;super.init()
        let application=submenu("咸鱼说")
        add(application,"关于咸鱼说",#selector(NSApplication.orderFrontStandardAboutPanel(_:)),target:NSApp)
        add(application,"检查更新…",#selector(checkUpdates(_:)),target:self)
        application.addItem(.separator())
        add(application,"设置…",#selector(openSettings(_:)),key:",",target:self)
        application.addItem(.separator())
        let services=NSMenu(title:"服务");let serviceItem=NSMenuItem(title:"服务",action:nil,keyEquivalent:"");serviceItem.submenu=services;application.addItem(serviceItem);NSApp.servicesMenu=services
        application.addItem(.separator())
        add(application,"隐藏咸鱼说",#selector(NSApplication.hide(_:)),key:"h",target:NSApp)
        let hideOthers=add(application,"隐藏其他应用",#selector(NSApplication.hideOtherApplications(_:)),key:"h",target:NSApp);hideOthers.keyEquivalentModifierMask=[.command,.option]
        add(application,"显示全部",#selector(NSApplication.unhideAllApplications(_:)),target:NSApp)
        application.addItem(.separator());add(application,"退出咸鱼说",#selector(NSApplication.terminate(_:)),key:"q",target:NSApp)
        let file=submenu("文件");add(file,"关闭窗口",#selector(NSWindow.performClose(_:)),key:"w")
        let edit=submenu("编辑")
        add(edit,"撤销",Selector(("undo:")),key:"z")
        let redo=add(edit,"重做",Selector(("redo:")),key:"z");redo.keyEquivalentModifierMask=[.command,.shift]
        edit.addItem(.separator())
        add(edit,"剪切",#selector(NSText.cut(_:)),key:"x");add(edit,"复制",#selector(NSText.copy(_:)),key:"c")
        add(edit,"粘贴",#selector(NSText.paste(_:)),key:"v");add(edit,"删除",#selector(NSText.delete(_:)))
        edit.addItem(.separator());add(edit,"全选",#selector(NSText.selectAll(_:)),key:"a")
        let view=submenu("显示");let fullscreen=add(view,"进入全屏幕",#selector(NSWindow.toggleFullScreen(_:)),key:"f");fullscreen.keyEquivalentModifierMask=[.command,.control]
        let windows=submenu("窗口");add(windows,"最小化",#selector(NSWindow.performMiniaturize(_:)),key:"m");add(windows,"缩放",#selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu=windows
        let help=submenu("帮助");add(help,"使用引导…",#selector(openOnboarding(_:)),target:self);add(help,"关于与本地隐私",#selector(openAbout(_:)),target:self);NSApp.helpMenu=help
        NSApp.mainMenu=menu
        RuntimeDiagnostics.event("native_menu_created")
    }
    private func submenu(_ title:String)->NSMenu {
        let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let value=NSMenu(title:title);item.submenu=value;menu.addItem(item);return value
    }
    @discardableResult private func add(_ menu:NSMenu,_ title:String,_ action:Selector,key:String="",target:AnyObject?=nil)->NSMenuItem {
        let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.target=target;menu.addItem(item);return item
    }
    @objc nonisolated private func openOnboarding(_ sender:Any?){DefaultModeAction.enqueue{[weak self]in self?.app.startOnboarding()}}
    @objc nonisolated private func openSettings(_ sender:Any?){DefaultModeAction.enqueue{[weak self]in guard let self else{return};self.app.page="设置";self.app.showMain?()}}
    @objc nonisolated private func openAbout(_ sender:Any?){DefaultModeAction.enqueue{[weak self]in guard let self else{return};self.app.page="关于";self.app.showMain?()}}
    @objc nonisolated private func checkUpdates(_ sender:Any?){DefaultModeAction.enqueue{UpdateManager.shared.check()}}
}
