import AppKit
import Carbon

// Pure state machine: a modifier chord must never become a dictation tap.
struct SoloKeyState {
    enum Action:Equatable {case down,up,interrupt}
    var held=false,used=false,started=false
    mutating func interrupt()->[Action]{
        guard held else{return []};used=true
        if started {started=false;return [.interrupt]};return []
    }
    mutating func change(down:Bool,hold:Bool,blocked:Bool)->[Action]{
        if down {
            guard !held else{return blocked ? interrupt():[]}
            held=true;used=blocked;started=hold && !blocked
            return started ? [.down]:[]
        }
        guard held else{return []}
        defer{held=false;used=false;started=false}
        if started{return [.up]}
        return !hold && !used ? [.down,.up]:[]
    }
}
final class HotkeyManager {
    private var refs:[EventHotKeyRef]=[]
    private var handler:EventHandlerRef?
    private var monitors:[Any]=[]
    private var bindings:[UInt32:KeyBinding]=[:]
    private var pressed=Set<UInt32>()
    private var solos:[UInt32:SoloKeyState]=[:]
    var standaloneHold=false
    var onStandaloneInterrupted:(()->Void)?
    var onAction:((UInt32,Bool)->Void)?
    var onEscape:(()->Void)?
    var onCommit:(()->Void)?
    var errors:[String]=[]
    var suppress=false {
        didSet {
            guard oldValue != suppress else{return}
            if suppress{refs.forEach{UnregisterEventHotKey($0)};refs=[];pressed=[];solos=[:]}
            else if let first=bindings[1],let second=bindings[2]{configure(first,second)}
        }
    }
    init(){
        var types=[EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed)),EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(),{_,event,context in
            guard let event,let context else{return OSStatus(eventNotHandledErr)}
            let manager=Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
            var id=EventHotKeyID();GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            manager.receive(id.id,down:GetEventKind(event)==UInt32(kEventHotKeyPressed));return noErr
        },types.count,&types,Unmanaged.passUnretained(self).toOpaque(),&handler)
        refreshMonitors()
    }
    func refreshMonitors(){
        monitors.forEach{NSEvent.removeMonitor($0)};monitors=[]
        if let monitor=NSEvent.addGlobalMonitorForEvents(matching:[.flagsChanged,.keyDown],handler:{[weak self]in self?.monitor($0)}) {monitors.append(monitor)}
        if let monitor=NSEvent.addLocalMonitorForEvents(matching:[.flagsChanged,.keyDown],handler:{[weak self] event in self?.monitor(event);return event}){monitors.append(monitor)}
    }
    func configure(_ first:KeyBinding,_ second:KeyBinding) {
        refs.forEach{UnregisterEventHotKey($0)};refs=[];pressed=[];solos=[:];bindings=[1:first,2:second];errors=[]
        guard !first.matches(second) else {errors=["听写与翻译快捷键不能相同。"];return}
        guard !suppress else{return}
        for (id,binding) in bindings {
            if !binding.standalone.isEmpty {solos[id]=SoloKeyState();continue}
            var ref:EventHotKeyRef?
            let result=RegisterEventHotKey(binding.key,binding.modifiers,EventHotKeyID(signature:0x44594150,id:id),GetApplicationEventTarget(),0,&ref)
            if result==noErr,let ref {refs.append(ref)}else{errors.append("\(binding.label) 无法注册，可能已被其他应用占用。")}
        }
    }
    private func receive(_ id:UInt32,down:Bool) {
        guard !suppress else{return}
        if down {guard pressed.insert(id).inserted else{return}}else{guard pressed.remove(id) != nil else{return}}
        onAction?(id,down)
    }
    private func dispatch(_ actions:[SoloKeyState.Action],id:UInt32){
        for action in actions {switch action {
        case .down:receive(id,down:true)
        case .up:receive(id,down:false)
        case .interrupt:pressed.remove(id);onStandaloneInterrupted?()
        }}
    }
    private func monitor(_ event:NSEvent){
        guard !suppress else{return}
        if event.type == .keyDown {
            for id in Array(solos.keys){let actions=solos[id]!.interrupt();dispatch(actions,id:id)}
            if event.keyCode==53 {onEscape?()}
            if [36,76].contains(event.keyCode),!event.modifierFlags.contains(.shift){onCommit?()}
            return
        }
        guard event.type == .flagsChanged else{return}
        for (id,binding) in bindings where !binding.standalone.isEmpty {
            let flags=event.modifierFlags
            var forbidden=flags.intersection([.command,.control,.shift])
            if binding.key==63 {forbidden.formUnion(flags.intersection(.option))}
            let blocked = !forbidden.isEmpty || (binding.key==61 && flags.rawValue & 0x20 != 0)
            if event.keyCode==binding.key {
                let actions=solos[id,default:SoloKeyState()].change(down:KeyBinding.modifierDown(key:binding.key,flags:flags.rawValue),hold:standaloneHold,blocked:blocked)
                dispatch(actions,id:id)
            }else if blocked || event.keyCode != binding.key {
                let actions=solos[id,default:SoloKeyState()].interrupt();dispatch(actions,id:id)
            }
        }
    }
    deinit {refs.forEach{UnregisterEventHotKey($0)};if let handler{RemoveEventHandler(handler)};monitors.forEach{NSEvent.removeMonitor($0)}}
}

enum ShortcutInput {
    static func glyphs(_ flags:NSEvent.ModifierFlags)->[String]{
        [(NSEvent.ModifierFlags.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")].compactMap{flags.contains($0.0) ? $0.1:nil}
    }
    static func binding(_ event:NSEvent)->KeyBinding? {
        var carbon:UInt32=0
        let flags=event.modifierFlags
        for (flag,mask) in [(NSEvent.ModifierFlags.control,UInt32(controlKey)),(.option,UInt32(optionKey)),(.shift,UInt32(shiftKey)),(.command,UInt32(cmdKey))] where flags.contains(flag){carbon|=mask}
        let names:[UInt16:String]=[122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",49:"Space",36:"Return"]
        guard carbon != 0 || names[event.keyCode]?.hasPrefix("F")==true else{return nil}
        guard let main=names[event.keyCode] ?? event.characters(byApplyingModifiers:[])?.uppercased(),!main.isEmpty else{return nil}
        return KeyBinding(key:UInt32(event.keyCode),modifiers:carbon,standalone:"",label:glyphs(flags).joined()+main)
    }
}
