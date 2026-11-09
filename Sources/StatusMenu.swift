import AppKit
import Combine

/// The menu owns one native view tree for its entire lifetime. In particular, opening
/// it must not destroy/recreate a SwiftUI hosting graph inside AppKit's tracking loop.
@MainActor final class StatusMenuController:NSObject {
    let menu=NSMenu()
    let status:NSStatusItem
    private let app:AppState
    enum Action:String {case toggleRecording,translate,cancelTask,copyLast,changeCleanup,changeAppearance,showWindow,hideWindow,openPage,quit}
    private let onAction:@MainActor (Action,Int)->Void
    private let header=StatusMenuHeader()
    private var subscription:AnyCancellable?
    private var appearanceSubscription:AnyCancellable?
    private var systemAppearanceSubscription:AnyCancellable?
    private(set) var presenting=false
    private var dictation:NSMenuItem!
    private var translation:NSMenuItem!
    private var cancel:NSMenuItem!
    private var copy:NSMenuItem!
    private var quit:NSMenuItem!
    private var cleanup:[NSMenuItem]=[]
    private var appearances:[NSMenuItem]=[]
    private var last:Snapshot?
    struct Snapshot:Equatable {
        let busy:Bool,capturing:Bool,hasResult:Bool
        let stage:String,cleanup:CleanupMode,appearance:String
        let dark:Bool
    }
    init(app:AppState,onAction:@escaping @MainActor (Action,Int)->Void){
        self.app=app;self.onAction=onAction
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        super.init()
        status.button?.image=DianyuDesign.mark(size:18,menu:true)
        status.button?.setAccessibilityLabel("咸鱼说菜单")
        menu.autoenablesItems=false
        menu.minimumWidth=StatusMenuPlacement.minimumWidth
        let brand=NSMenuItem();brand.view=header;menu.addItem(brand);menu.addItem(.separator())
        dictation=item("开始听写","toggleRecording","mic")
        translation=item("直接出英文","translate","translate")
        cancel=item("取消并保留录音","cancelTask","xmark.circle")
        copy=item("复制最近结果","copyLast","doc.on.doc")
        menu.addItem(.separator())
        let level=NSMenuItem(title:"整理程度",action:nil,keyEquivalent:"")
        let levels=NSMenu();levels.autoenablesItems=false
        for (index,mode) in CleanupMode.allCases.enumerated(){
            let entry=NSMenuItem(title:mode.title,action:#selector(performAction(_:)),keyEquivalent:"")
            entry.target=self;entry.identifier=NSUserInterfaceItemIdentifier(Action.changeCleanup.rawValue);entry.tag=index;levels.addItem(entry);cleanup.append(entry)
        }
        level.submenu=levels;menu.addItem(level)
        let appearance=NSMenuItem(title:"外观",action:nil,keyEquivalent:"")
        let themes=NSMenu();themes.autoenablesItems=false
        for (index,title) in ["跟随系统","浅色","深色"].enumerated(){
            let entry=NSMenuItem(title:title,action:#selector(performAction(_:)),keyEquivalent:"")
            entry.target=self;entry.identifier=NSUserInterfaceItemIdentifier(Action.changeAppearance.rawValue);entry.tag=index;themes.addItem(entry);appearances.append(entry)
        }
        appearance.submenu=themes;menu.addItem(appearance);menu.addItem(.separator())
        _=item("打开咸鱼说","showWindow","macwindow")
        for (title,index,symbol) in [("历史记录",1,"clock.arrow.circlepath"),("个人词表",2,"text.book.closed"),("统计",3,"chart.bar.xaxis"),("设置…",4,"slider.horizontal.3")]{
            let entry=item(title,"openPage:",symbol);entry.tag=index
        }
        _=item("隐藏窗口，保持运行","hideWindow","rectangle.compress.vertical")
        menu.addItem(.separator());quit=item("退出咸鱼说","quit","power");quit.keyEquivalent="q"
        refresh()
        status.button?.target=self;status.button?.action=#selector(toggleMenu(_:))
        status.button?.sendAction(on:[.leftMouseDown,.rightMouseDown])
        // objectWillChange fires before the new values are stored. Deliver on the
        // default run-loop mode, after the mutation and outside menu tracking.
        // The snapshot also prevents elapsed/meter publications from rewriting menus.
        subscription=app.objectWillChange.receive(on:RunLoop.main).sink{[weak self] in
            self?.refresh()
        }
        appearanceSubscription=NotificationCenter.default.publisher(for:UserDefaults.didChangeNotification)
            .receive(on:RunLoop.main).sink{[weak self] _ in self?.refresh()}
        systemAppearanceSubscription=NSApp.publisher(for:\.effectiveAppearance)
            .receive(on:RunLoop.main).sink{[weak self] _ in self?.refresh()}
    }
    // ObjC/AppKit enters synchronously from outside Swift concurrency. A plain
    // main-queue bridge establishes the execution context before touching UI.
    @objc nonisolated private func toggleMenu(_ sender:Any?){
        DispatchQueue.main.async{[weak self] in self?.presentMenu()}
    }
    @objc nonisolated func performAction(_ sender:NSMenuItem){
        DefaultModeAction.enqueue{[weak self] in
            guard let self,let name=sender.identifier?.rawValue,let action=Action(rawValue:name) else{return}
            // Only our retained menu items may route an action. Do not accept a
            // stale or foreign sender supplied by an accessibility callback.
            var owned=false
            for entry in self.menu.items {
                if entry === sender{owned=true;break}
                if let submenu=entry.submenu{for child in submenu.items where child === sender{owned=true;break}}
            }
            guard owned,!sender.isHidden,sender.isEnabled else{return}
            if self.presenting{self.menu.cancelTracking()}
            RuntimeDiagnostics.event("menu_action",field:action.rawValue)
            self.onAction(action,sender.tag)
        }
    }
    private func presentMenu(){
        guard !presenting else{menu.cancelTracking();return}
        guard let button=status.button,let window=button.window,let screen=window.screen else{return}
        // Finish all content/layout changes before capturing one immutable screen
        // anchor. MenuBarAgent can move the button's hosting view during tracking.
        refresh();menu.update()
        let frame=window.convertToScreen(button.convert(button.bounds,to:nil))
        let origin=StatusMenuPlacement.topLeft(button:frame,menu:menu.size,visible:screen.visibleFrame)
        presenting=true;RuntimeDiagnostics.event("menu_open")
        button.highlight(true)
        defer{button.highlight(false);presenting=false;refresh();RuntimeDiagnostics.event("menu_close")}
        // Keep the status-button association so MenuBarAgent exports the popup
        // and its actions for accessibility. Position is computed and clamped
        // in screen coordinates once, then converted back for AppKit.
        let location=button.convert(window.convertPoint(fromScreen:origin),from:nil)
        menu.popUp(positioning:nil,at:location,in:button)
    }
    private func item(_ title:String,_ action:String,_ symbol:String)->NSMenuItem{
        let value=NSMenuItem(title:title,action:#selector(performAction(_:)),keyEquivalent:"")
        value.identifier=NSUserInterfaceItemIdentifier(action.replacingOccurrences(of:":",with:""));value.target=self;value.image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)
        menu.addItem(value);return value
    }
    func refresh(){
        // Treat an open menu as a snapshot. Changing hidden rows or custom-view
        // content while AppKit is tracking can resize/reposition its window.
        guard !presenting else{return}
        let record=app.latestRecord
        let selected=UserDefaults.standard.string(forKey:DianyuDesign.appearanceKey) ?? "system"
        let systemDark=NSApp.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        let next=Snapshot(busy:app.busy,capturing:app.capturing,hasResult:record.map{!$0.output.isEmpty || !$0.raw.isEmpty} ?? false,stage:app.stage,cleanup:app.store.preferences.cleanup,appearance:selected,dark:selected=="dark" || (selected=="system" && systemDark))
        guard next != last else{return}
        let appearanceChanged=last?.dark != next.dark;last=next
        if appearanceChanged{StatusMenuAppearance.apply(menu,dark:next.dark)}
        header.update(busy:next.busy,stage:next.stage)
        dictation.title=next.capturing ? "结束听写":"开始听写"
        dictation.image=NSImage(systemSymbolName:next.capturing ? "stop.circle":"mic",accessibilityDescription:nil)
        dictation.isEnabled = !next.busy || next.capturing
        translation.isEnabled = !next.busy;cancel.isHidden = !next.busy
        copy.isEnabled=next.hasResult;quit.isEnabled = !next.busy
        for (index,entry) in cleanup.enumerated(){entry.isEnabled = !next.busy;entry.state=CleanupMode.allCases[index]==next.cleanup ? .on:.off}
        for (index,entry) in appearances.enumerated(){entry.state=["system","light","dark"][index]==next.appearance ? .on:.off}
    }
    func invalidate(){subscription?.cancel();subscription=nil;appearanceSubscription?.cancel();appearanceSubscription=nil;systemAppearanceSubscription?.cancel();systemAppearanceSubscription=nil;menu.cancelTracking();status.button?.target=nil;status.button?.action=nil;status.menu=nil;NSStatusBar.system.removeStatusItem(status)}
}

/// MenuBarAgent can host the popup under a different appearance than our window.
/// Explicitly propagate the same native appearance through the retained tree.
enum StatusMenuAppearance {
    static func apply(_ menu:NSMenu,dark:Bool){
        let appearance=NSAppearance(named:dark ? .darkAqua:.aqua)
        menu.appearance=appearance
        for item in menu.items{
            item.view?.appearance=appearance
            if let submenu=item.submenu{apply(submenu,dark:dark)}
        }
    }
}

/// Native text/image controls also let MenuBarAgent export the menu without entering
/// a transient SwiftUI accessibility graph. Layout/branding matches the former header.
@MainActor final class StatusMenuHeader:NSView {
    private let detail=NSTextField(labelWithString:"")
    private let dot=NSView()
    init(){
        super.init(frame:NSRect(x:0,y:0,width:284,height:70))
        let logo=NSImageView(frame:NSRect(x:18,y:19,width:32,height:32));logo.image=DianyuDesign.mark(size:32);logo.contentTintColor = .labelColor;addSubview(logo)
        let title=NSTextField(labelWithString:"咸鱼说");title.frame=NSRect(x:62,y:36,width:140,height:20);title.font = .systemFont(ofSize:15,weight:.semibold);addSubview(title)
        let version=NSTextField(labelWithString:DianyuDesign.version);version.frame=NSRect(x:204,y:38,width:62,height:16);version.alignment = .right;version.font = .systemFont(ofSize:11);version.textColor = .secondaryLabelColor;addSubview(version)
        dot.frame=NSRect(x:63,y:21,width:4,height:4);dot.wantsLayer=true;dot.layer?.cornerRadius=2;addSubview(dot)
        detail.frame=NSRect(x:72,y:15,width:194,height:16);detail.font = .systemFont(ofSize:11);detail.textColor = .secondaryLabelColor;detail.lineBreakMode = .byTruncatingTail;addSubview(detail)
        setAccessibilityElement(true);setAccessibilityRole(.staticText)
    }
    required init?(coder:NSCoder){nil}
    func update(busy:Bool,stage:String){
        detail.stringValue=busy ? stage:"完全本地 · 随时听写"
        dot.layer?.backgroundColor=(busy ? NSColor.systemCyan:NSColor.systemGreen).cgColor
        setAccessibilityLabel("咸鱼说 \(DianyuDesign.version) \(detail.stringValue)")
    }
}
