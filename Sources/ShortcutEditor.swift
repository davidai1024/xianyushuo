import AppKit
import SwiftUI

/// Inline native control. Exactly one custom surface, with no NSButtonCell.
final class ShortcutField:NSControl {
    var binding=KeyBinding(){didSet{if !editing{caption=binding.label;setAccessibilityValue(binding.label)}}}
    var selected=false{didSet{needsDisplay=true}}
    var begin:(()->Void)?
    var end:(()->Void)?
    var preview:(([String])->Void)?
    var commit:((KeyBinding)->Bool)?
    private(set) var editing=false
    private var caption=""{didSet{needsDisplay=true}}
    private var pending:KeyBinding?
    private var solo:UInt16?
    private var soloUsed=false
    private var eventMonitor:Any?
    private var observers:[NSObjectProtocol]=[]
    private var tracking:NSTrackingArea?
    private var hovered=false
    override init(frame:NSRect){super.init(frame:frame);focusRingType = .none;setAccessibilityElement(true);setAccessibilityRole(.button)}
    required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}
    override var acceptsFirstResponder:Bool{true}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func mouseDown(with event:NSEvent){startEditing()}
    override func accessibilityPerformPress()->Bool{startEditing();return true}
    override func becomeFirstResponder()->Bool{needsDisplay=true;return true}
    override func resignFirstResponder()->Bool{cancelEditing();return true}
    override func viewWillMove(toWindow newWindow:NSWindow?){if newWindow==nil{cancelEditing()};super.viewWillMove(toWindow:newWindow)}
    override func keyDown(with event:NSEvent){if editing{consume(event)}else if event.keyCode==36 || event.keyCode==49{startEditing()}else{super.keyDown(with:event)}}
    override func performKeyEquivalent(with event:NSEvent)->Bool{if editing{consume(event);return true};return super.performKeyEquivalent(with:event)}
    override func updateTrackingAreas(){
        super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)}
        let next=NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.inVisibleRect,.mouseEnteredAndExited],owner:self);addTrackingArea(next);tracking=next
    }
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();needsDisplay=true}
    override func draw(_ dirtyRect:NSRect){
        let path=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:7,yRadius:7)
        NSColor.controlBackgroundColor.setFill();path.fill()
        if editing{NSColor.systemBlue.withAlphaComponent(0.08).setFill();path.fill()}
        (editing ? NSColor.systemBlue:NSColor.separatorColor.withAlphaComponent(hovered || selected ? 0.85:0.45)).setStroke();path.lineWidth=editing ? 2:1;path.stroke()
        let paragraph=NSMutableParagraphStyle();paragraph.alignment = .center;paragraph.lineBreakMode = .byTruncatingTail
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13,weight:.medium),.foregroundColor:editing ? NSColor.systemBlue:NSColor.labelColor,.paragraphStyle:paragraph]
        let text=caption as NSString,height=text.size(withAttributes:attributes).height
        text.draw(in:NSRect(x:7,y:(bounds.height-height)/2,width:bounds.width-14,height:height),withAttributes:attributes)
    }
    func startEditing(){
        guard !editing,window?.makeFirstResponder(self)==true else{return}
        editing=true;pending=nil;solo=nil;soloUsed=false;caption=binding.label;begin?();preview?([])
        setAccessibilityValue("正在录制快捷键");needsDisplay=true
        eventMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged,.leftMouseDown,.rightMouseDown]){[weak self]event in
            guard let self,self.editing else{return event}
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                if event.window !== self.window || !self.bounds.contains(self.convert(event.locationInWindow,from:nil)){self.cancelEditing()}
                return event
            }
            guard event.window === self.window else{self.cancelEditing();return event}
            self.consume(event);return nil
        }
        if let window{
            for name in [NSWindow.didResignKeyNotification,NSWindow.willCloseNotification]{
                observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self]_ in self?.cancelEditing()})
            }
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main){[weak self]_ in self?.cancelEditing()})
    }
    func cancelEditing(){
        guard editing else{return};editing=false;pending=nil;solo=nil
        if let eventMonitor{NSEvent.removeMonitor(eventMonitor)};eventMonitor=nil
        observers.forEach{NotificationCenter.default.removeObserver($0)};observers=[]
        caption=binding.label;setAccessibilityValue(binding.label);preview?([]);end?()
    }
    private func accept(_ value:KeyBinding){
        if commit?(value)==true{binding=value;cancelEditing();window?.makeFirstResponder(nil)}
        else{pending=nil;solo=nil;soloUsed=true;caption="请换一个按键";preview?([])}
    }
    private func consume(_ event:NSEvent){
        if event.type == .flagsChanged {
            if let solo,event.keyCode==solo,!KeyBinding.modifierDown(key:UInt32(solo),flags:event.modifierFlags.rawValue){
                if !soloUsed{accept(solo==61 ? KeyBinding():KeyBinding(key:63,modifiers:0,standalone:"fn",label:"Fn"))};self.solo=nil;return
            }
            let flags=event.modifierFlags
            let isolated=flags.intersection([.control,.command,.shift,.option]).isEmpty || (event.keyCode==61 && flags.intersection([.control,.command,.shift]).isEmpty && flags.rawValue & 0x20==0)
            if [UInt16(61),63].contains(event.keyCode),KeyBinding.modifierDown(key:UInt32(event.keyCode),flags:flags.rawValue),isolated{solo=event.keyCode;soloUsed=false}
            else if solo != nil{soloUsed=true}
            let keys=solo==61 ? ["右侧","⌥"]:solo==63 ? ["Fn"]:ShortcutInput.glyphs(flags)
            preview?(keys);if pending==nil{caption=keys.isEmpty ? binding.label:keys.joined()+" …"};return
        }
        if event.type == .keyUp{if let pending,pending.key==event.keyCode{accept(pending)};return}
        guard event.type == .keyDown,!event.isARepeat else{return};soloUsed=true
        if event.keyCode==53{cancelEditing();window?.makeFirstResponder(nil);return}
        if let value=ShortcutInput.binding(event){pending=value;caption=value.label;preview?(value.keycaps)}
        else{pending=nil;caption="请加修饰键";preview?(ShortcutInput.glyphs(event.modifierFlags))}
    }
    deinit{if let eventMonitor{NSEvent.removeMonitor(eventMonitor)};observers.forEach{NotificationCenter.default.removeObserver($0)}}
}
struct InlineShortcut:NSViewRepresentable {
    let binding:KeyBinding
    let selected:Bool
    let onBegin:()->Void
    let onEnd:()->Void
    let onPreview:([String])->Void
    let onCommit:(KeyBinding)->Bool
    func makeNSView(context:Context)->ShortcutField{let field=ShortcutField();field.toolTip="点击录制；松键保存，Esc 或点外部取消。";return field}
    func updateNSView(_ field:ShortcutField,context:Context){field.binding=binding;field.selected=selected;field.begin=onBegin;field.end=onEnd;field.preview=onPreview;field.commit=onCommit;field.setAccessibilityLabel("更改快捷键 "+binding.label)}
    static func dismantleNSView(_ field:ShortcutField,coordinator:()){field.cancelEditing()}
}
