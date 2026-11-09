import SwiftUI
import AppKit

// Explicit public property-wrapper type; the macOS 27 SDK also exports a
// same-named @State macro whose plugin is not shipped in Command Line Tools.
// This alias retains State<Value> storage and DynamicProperty semantics.
typealias UIState<Value> = SwiftUI.State<Value>

/// Dianyu v4: a single navigation glass surface; all persistent content is flat.
enum DianyuDesign {
    static let sidebarWidth:CGFloat=224
    static let sidebarInset:CGFloat=12
    static let sidebarRadius:CGFloat=24
    static let contentInset:CGFloat=24
    static let appearanceKey="dianyu.appearance"
    static let accent=Color(red:102/255,green:253/255,blue:254/255)
    static let accentInk=Color(red:8/255,green:36/255,blue:38/255)
    static let focus=Color(red:117/255,green:184/255,blue:1)
    static let accentHover=Color(red:151/255,green:1,blue:1)
    static func adaptive(_ name:String,dark:UInt32,light:UInt32)->Color{
        Color(nsColor:NSColor(name:NSColor.Name(name)){appearance in
            let value=appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light
            return NSColor(srgbRed:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255,alpha:1)
        })
    }
    static let page=adaptive("DianyuPage",dark:0x212222,light:0xF5F5F4)
    static let group=adaptive("DianyuGroup",dark:0x1E2020,light:0xFFFFFF)
    static let feature=adaptive("DianyuFeature",dark:0x262929,light:0xEBEDEC)
    static let inset=adaptive("DianyuInset",dark:0x1D2020,light:0xF0F1F0)
    static let control=adaptive("DianyuControl",dark:0x353939,light:0xE5E7E6)
    static let selection=adaptive("DianyuSelection",dark:0x494E4E,light:0xD8DEDC)
    static let secondary=adaptive("DianyuSecondary",dark:0xA1A9AA,light:0x58615F)
    static let tertiary=adaptive("DianyuTertiary",dark:0x83948D,light:0x69716F)
    static let primary=adaptive("DianyuText",dark:0xE8EBEB,light:0x202424)
    static let onGlassMuted=adaptive("DianyuGlassText",dark:0xD5E0E1,light:0x4C5758)
    static let segmentTrack=adaptive("DianyuTrack",dark:0x2A2D2D,light:0xE6E9E8)
    static let hover=adaptive("DianyuHover",dark:0x414646,light:0xDAE0DE)
    static let pressed=adaptive("DianyuPressed",dark:0x2E3232,light:0xCDD5D2)
    static let line=Color.primary.opacity(0.05)
    static var version:String{Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString")as?String ?? ""}
    static var scheme:ColorScheme?{
        switch UserDefaults.standard.string(forKey:appearanceKey){case "dark":return .dark;case "light":return .light;default:return nil}
    }
    @MainActor static func applyAppearance(){
        NSApp.appearance=scheme == .dark ? NSAppearance(named:.darkAqua):scheme == .light ? NSAppearance(named:.aqua):nil
    }
    private static func template(_ name:String)->NSImage?{
        guard let url=Bundle.main.url(forResource:name,withExtension:"png"),let image=NSImage(contentsOf:url)else{return nil};image.isTemplate=true;return image
    }
    private static let brandTemplate=template("BrandMark")
    private static let menuTemplate=template("MenuBarIcon@2x")
    static func mark(size:CGFloat,menu:Bool=false)->NSImage?{
        guard let image=(menu ? menuTemplate:brandTemplate)?.copy()as?NSImage else{return nil}
        image.size=NSSize(width:size,height:size);image.isTemplate=true;return image
    }
}
struct BrandMark:View {
    var size:CGFloat=34
    var body:some View{
        Group{if let image=DianyuDesign.mark(size:size){Image(nsImage:image).resizable().renderingMode(.template).scaledToFit()}else{Image(systemName:"mic.fill").resizable().scaledToFit()}}
            .frame(width:size,height:size).accessibilityHidden(true)
    }
}
struct FlatButtonStyle:ButtonStyle {
    enum Kind{case standard,primary,quiet,danger}
    var kind:Kind = .standard
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @UIState private var hovered=false
    @ObservedObject private var focusFeedback=KeyboardFocusFeedback.shared
    func makeBody(configuration:Configuration)->some View{
        configuration.label.font(.system(size:13,weight:.semibold)).padding(.horizontal,kind == .quiet ? 7:12).frame(minWidth:kind == .quiet ? 30:0,minHeight:30)
            .foregroundStyle(kind == .primary ? DianyuDesign.accentInk:kind == .danger ? Color.red:Color.primary)
            .background(kind == .primary ? (hovered ? DianyuDesign.accentHover:DianyuDesign.accent):kind == .quiet ? Color.primary.opacity(hovered ? 0.06:0):(configuration.isPressed ? DianyuDesign.pressed:hovered ? DianyuDesign.hover:DianyuDesign.control),in:RoundedRectangle(cornerRadius:8))
            .overlay{if kind != .quiet{RoundedRectangle(cornerRadius:8).strokeBorder(DianyuDesign.line,lineWidth:1)}}
            .overlay(RoundedRectangle(cornerRadius:8).fill(Color.primary.opacity(configuration.isPressed ? 0.10:hovered ? 0.035:0)))
            .contentShape(Rectangle()).textSelection(.disabled)
            .overlay{if focused && focusFeedback.visible{RoundedRectangle(cornerRadius:10).strokeBorder(DianyuDesign.focus,lineWidth:2).padding(-3)}}
            .opacity(enabled ? 1:0.42).onHover{hovered=$0}
    }
}
struct FlatSegmented<Value:Hashable>:View {
    let label:String
    @Binding var selection:Value
    let options:[(String,Value)]
    @FocusState private var focused:Value?
    @ObservedObject private var focusFeedback=KeyboardFocusFeedback.shared
    var body:some View{
        HStack(spacing:3){ForEach(options.indices,id:\.self){i in
            Button{selection=options[i].1}label:{Text(options[i].0).font(.system(size:12,weight:.semibold)).lineLimit(1).padding(.horizontal,12).frame(minHeight:28).frame(maxWidth:.infinity)
                .foregroundStyle(selection==options[i].1 ? Color.primary:DianyuDesign.secondary)
                .background(selection==options[i].1 ? DianyuDesign.selection:Color.clear,in:RoundedRectangle(cornerRadius:6)).contentShape(Rectangle()).textSelection(.disabled)}
                .buttonStyle(.plain).focusable().focusEffectDisabled().focused($focused,equals:options[i].1)
                .accessibilityAddTraits(selection==options[i].1 ? [.isSelected]:[])
                .overlay{if focused==options[i].1 && focusFeedback.visible{RoundedRectangle(cornerRadius:8).strokeBorder(DianyuDesign.focus,lineWidth:2).padding(-2).allowsHitTesting(false)}}
        }}.padding(4).background(DianyuDesign.segmentTrack,in:RoundedRectangle(cornerRadius:8))
            .accessibilityElement(children:.contain).accessibilityLabel(label)
    }
}
struct FlatMenuPicker<Value:Hashable>:View {
    let label:String
    @Binding var selection:Value
    let options:[(String,Value)]
    var body:some View{
        Menu{ForEach(options.indices,id:\.self){i in Button{selection=options[i].1}label:{
            if selection==options[i].1{Label(options[i].0,systemImage:"checkmark")}else{Text(options[i].0)}
        }}}label:{Text(options.first(where:{$0.1==selection})?.0 ?? "未选择").font(.system(size:12)).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)}
            .menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.primary).foregroundStyle(.primary)
            .padding(.leading,10).padding(.trailing,22).frame(height:30).background(DianyuDesign.control,in:RoundedRectangle(cornerRadius:8))
            .overlay(alignment:.trailing){Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold)).foregroundStyle(DianyuDesign.secondary).padding(.trailing,9).allowsHitTesting(false)}
            .accessibilityLabel(label)
    }
}
struct SearchField:View {
    let placeholder:String
    @Binding var text:String
    var focusRequest:Binding<Bool>?=nil
    @FocusState private var focused:Bool
    var body:some View{
        HStack(spacing:8){Image(systemName:"magnifyingglass").foregroundStyle(DianyuDesign.secondary);TextField(placeholder,text:$text).textFieldStyle(.plain).font(.system(size:12)).accessibilityLabel(placeholder).focused($focused);if !text.isEmpty{Button{text=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(DianyuDesign.secondary).frame(width:24,height:24).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel("清除搜索")}}
            .padding(.horizontal,10).frame(height:32).background(DianyuDesign.control.opacity(0.58),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(focused ? DianyuDesign.focus:DianyuDesign.line,lineWidth:focused ? 2:1))
            .onChange(of:focusRequest?.wrappedValue){requested in if requested==true{focused=true;if let request=focusRequest{request.wrappedValue=false}}}
    }
}
struct FlatEmptyState:View {
    let title:String
    let detail:String
    let symbol:String
    var body:some View{VStack(spacing:12){Image(systemName:symbol).font(.system(size:28,weight:.light)).foregroundStyle(DianyuDesign.tertiary);Text(title).font(.system(size:17,weight:.semibold));Text(detail).font(.system(size:13)).foregroundStyle(DianyuDesign.secondary).multilineTextAlignment(.center).frame(maxWidth:350)}.padding(32).frame(maxWidth:.infinity,maxHeight:.infinity)}
}
struct VocabularyWordLabel:View {
    let word:String
    var body:some View{Text(word).font(.system(size:13,weight:.medium)).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)}
}
struct WindowBackdrop:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView{let v=NSVisualEffectView();v.material = .underWindowBackground;v.blendingMode = .behindWindow;v.state = .active;return v}
    func updateNSView(_ view:NSVisualEffectView,context:Context){}
}
final class ClearHostingView<Content:View>:NSHostingView<Content>{override var isOpaque:Bool{false}}
/// NSGlassEffectView owns its SwiftUI content. No opaque view is layered over it.
struct NavigationGlass<Content:View & Equatable>:NSViewRepresentable,Equatable {
    let content:Content
    static func ==(lhs:Self,rhs:Self)->Bool{lhs.content==rhs.content}
    func makeNSView(context:Context)->NavigationGlassHost<Content>{NavigationGlassHost(content:content)}
    func updateNSView(_ view:NavigationGlassHost<Content>,context:Context){view.update(content)}
}
final class NavigationGlassHost<Content:View>:NSView {
    let hosting:ClearHostingView<Content>
    private var surface:NSView?
    private var observer:NSObjectProtocol?
    var usesSystemGlass:Bool{if #available(macOS 26.0,*){return surface is NSGlassEffectView};return false}
    init(content:Content){hosting=ClearHostingView(rootView:content);super.init(frame:.zero);hosting.sizingOptions=[];rebuild();observer=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main){[weak self]_ in self?.rebuild()}}
    required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}
    override var isOpaque:Bool{false}
    func update(_ content:Content){hosting.rootView=content}
    private func rebuild(){
        hosting.removeFromSuperview();surface?.removeFromSuperview()
        let view:NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency{
            let solid=NSView();solid.wantsLayer=true;solid.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor;solid.layer?.cornerRadius=24;solid.addSubview(hosting);view=solid
        }else if #available(macOS 26.0,*){
            let glass=NSGlassEffectView();glass.style = .regular;glass.cornerRadius=24;glass.contentView=hosting;view=glass
        }else{
            let fallback=NSVisualEffectView();fallback.material = .sidebar;fallback.blendingMode = .behindWindow;fallback.state = .active;fallback.wantsLayer=true;fallback.layer?.cornerRadius=24;fallback.layer?.masksToBounds=true;fallback.addSubview(hosting);view=fallback
        }
        view.frame=bounds;view.autoresizingMask=[.width,.height];addSubview(view);surface=view
        hosting.frame=view.bounds;hosting.autoresizingMask=[.width,.height]
        setAccessibilityIdentifier("floating-navigation-glass")
    }
    override func layout(){super.layout();surface?.frame=bounds;hosting.frame=surface?.bounds ?? bounds}
    deinit{if let observer{NSWorkspace.shared.notificationCenter.removeObserver(observer)}}
}
/// Native AppKit window-button factories, with their actions routed to this window.
/// Original titlebar buttons stay hidden; there is exactly one visible control set.
struct NativeWindowControls:NSViewRepresentable {
    func makeNSView(context:Context)->TrafficLightHost{TrafficLightHost()}
    func updateNSView(_ view:TrafficLightHost,context:Context){}
    static func dismantleNSView(_ view:TrafficLightHost,coordinator:()){view.restoreButtons()}
}
final class TrafficLightHost:NSView {
    private(set) var buttons:[NSButton]=[]
    private var originalVisibility:[(NSButton,Bool)]=[]
    private var observers:[NSObjectProtocol]=[]
    override init(frame:NSRect){super.init(frame:frame);setAccessibilityIdentifier("native-window-controls")}
    convenience init(){self.init(frame:.zero)}
    required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}
    override func viewDidMoveToWindow(){
        super.viewDidMoveToWindow();observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]
        if let window{
            for name in [NSWindow.didResizeNotification,NSWindow.didBecomeKeyNotification]{observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self]_ in DispatchQueue.main.async{self?.adoptButtons()}})}
        }
        DispatchQueue.main.async{[weak self]in self?.adoptButtons()}
    }
    func adoptButtons(){
        guard let window else{return}
        let kinds:[NSWindow.ButtonType]=[.closeButton,.miniaturizeButton,.zoomButton]
        for kind in kinds{if let original=window.standardWindowButton(kind){if !originalVisibility.contains(where:{$0.0 === original}){originalVisibility.append((original,original.isHidden))};original.isHidden=true}}
        if buttons.isEmpty{
            for (i,kind)in kinds.enumerated(){
                guard let button=NSWindow.standardWindowButton(kind,for:window.styleMask)else{continue}
                button.target=self;button.action=[#selector(closeWindow),#selector(minimizeWindow),#selector(zoomWindow)][i]
                button.setAccessibilityLabel(["关闭","最小化","全屏或缩放"][i]);button.setFrameSize(NSSize(width:14,height:14));addSubview(button);buttons.append(button)
            }
        }
        for (i,button)in buttons.enumerated(){button.isHidden=false;button.alphaValue=1;button.setFrameOrigin(NSPoint(x:9+CGFloat(i)*20,y:(bounds.height-14)/2));button.needsDisplay=true}
    }
    override func layout(){super.layout();adoptButtons()}
    @objc private func closeWindow(){window?.performClose(nil)}
    @objc private func minimizeWindow(){window?.performMiniaturize(nil)}
    @objc private func zoomWindow(){if NSApp.currentEvent?.modifierFlags.contains(.option)==true{window?.performZoom(nil)}else{window?.toggleFullScreen(nil)}}
    func restoreButtons(){originalVisibility.forEach{$0.0.isHidden=$0.1};originalVisibility=[];buttons.forEach{$0.removeFromSuperview()};buttons=[]}
    deinit{observers.forEach{NotificationCenter.default.removeObserver($0)}}
}
