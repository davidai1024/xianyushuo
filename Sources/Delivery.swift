import AppKit
import ApplicationServices
import CryptoKit

/// Only the focused input and its immediate ancestors, never a window-wide text dump.
enum InputAccess {
    static func value(_ element:AXUIElement,_ name:String)->CFTypeRef?{var result:CFTypeRef?;return AXUIElementCopyAttributeValue(element,name as CFString,&result) == .success ? result:nil}
    static func string(_ element:AXUIElement,_ name:String)->String?{
        if let text=value(element,name)as?String{return text}
        if let text=value(element,name)as?NSAttributedString{return text.string};return nil
    }
    static func range(_ element:AXUIElement)->CFRange?{
        guard let v=value(element,kAXSelectedTextRangeAttribute),CFGetTypeID(v)==AXValueGetTypeID()else{return nil}
        var range=CFRange();return AXValueGetValue(unsafeBitCast(v,to:AXValue.self),.cfRange,&range) ? range:nil
    }
    static func settable(_ element:AXUIElement,_ name:String)->Bool{var result:DarwinBoolean=false;return AXUIElementIsAttributeSettable(element,name as CFString,&result) == .success && result.boolValue}
    static func focused(pid:pid_t?=nil)->AXUIElement?{
        guard AXIsProcessTrusted()else{return nil}
        var candidates:[AXUIElement]=[]
        func append(_ v:CFTypeRef?){
            guard let v,CFGetTypeID(v)==AXUIElementGetTypeID()else{return}
            let element=unsafeBitCast(v,to:AXUIElement.self)
            if let pid{var owner:pid_t=0;guard AXUIElementGetPid(element,&owner) == .success,owner==pid else{return}}
            candidates.append(element)
        }
        if let pid{append(value(AXUIElementCreateApplication(pid),kAXFocusedUIElementAttribute))}
        append(value(AXUIElementCreateSystemWide(),kAXFocusedUIElementAttribute))
        // Some web shells temporarily expose an app/window as the application focus.
        // Prefer a real focused editor from the system query, with the same PID.
        return candidates.first(where:{editable($0) != nil}) ?? candidates.first
    }
    static func editable(_ focus:AXUIElement)->AXUIElement?{
        var current:AXUIElement?=focus
        for _ in 0..<4 {
            guard let element=current else{break}
            let role=string(element,kAXRoleAttribute) ?? "",subrole=string(element,kAXSubroleAttribute) ?? ""
            if subrole=="AXSecureTextField"{return nil}
            if let enabled=value(element,kAXEnabledAttribute)as?Bool,!enabled{return nil}
            if let editable=value(element,"AXEditable")as?Bool,!editable{return nil}
            if [kAXTextFieldRole,kAXTextAreaRole,kAXComboBoxRole].contains(role) || settable(element,kAXSelectedTextAttribute){return element}
            current=value(element,kAXParentAttribute).map{unsafeBitCast($0,to:AXUIElement.self)}
        }
        return nil
    }
    static func geometry(_ element:AXUIElement)->[Double]?{
        guard let p=value(element,kAXPositionAttribute),let s=value(element,kAXSizeAttribute),CFGetTypeID(p)==AXValueGetTypeID(),CFGetTypeID(s)==AXValueGetTypeID()else{return nil}
        var point=CGPoint.zero,size=CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p,to:AXValue.self),.cgPoint,&point),AXValueGetValue(unsafeBitCast(s,to:AXValue.self),.cgSize,&size)else{return nil}
        return [point.x,point.y,size.width,size.height]
    }
    static func hash(_ text:String)->String{SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()}
}
struct PasteTarget {
    var pid:pid_t?
    var bundleID:String
    var element:AXUIElement?
    var window:AXUIElement?
    var role:String
    var focusedRole:String
    var focusedOwner:pid_t?
    var identifier:String
    var geometry:[Double]?
    var text:String?
    var selection:CFRange?
    var clipboardVersion:Int
    var weChatContext:WeChatPasteContext?=nil
    static func capture()->PasteTarget{
        let app=NSWorkspace.shared.frontmostApplication
        let focus=InputAccess.focused(pid:app?.processIdentifier)
        let input=focus.flatMap{InputAccess.editable($0)}
        var owner:pid_t=0;if let focus{_ = AXUIElementGetPid(focus,&owner)}
        return PasteTarget(pid:app?.processIdentifier,bundleID:app?.bundleIdentifier ?? "",element:input,
            window:input.flatMap{InputAccess.value($0,kAXWindowAttribute)}.map{unsafeBitCast($0,to:AXUIElement.self)},
            role:input.flatMap{InputAccess.string($0,kAXRoleAttribute)} ?? "",focusedRole:focus.flatMap{InputAccess.string($0,kAXRoleAttribute)} ?? "",focusedOwner:owner>0 ? owner:nil,
            identifier:input.flatMap{InputAccess.string($0,kAXIdentifierAttribute)} ?? "",
            geometry:input.flatMap{InputAccess.geometry($0)},text:input.flatMap{InputAccess.string($0,kAXValueAttribute)},selection:input.flatMap{InputAccess.range($0)},clipboardVersion:NSPasteboard.general.changeCount)
    }
    var audit:[String:Any]{
        var info:[String:Any]=["bundle_id":bundleID,"accessibility_trusted":AXIsProcessTrusted(),"focused_editable_found":element != nil,"role":role,"focused_role":focusedRole,"focused_owner_pid":focusedOwner ?? 0,"foreground_pid":pid ?? 0,"identifier":identifier,"value_readable":text != nil,"selection_readable":selection != nil]
        if bundleID==WeChatPasteContext.bundleID{info["wechat_window_anchor"]=weChatContext != nil}
        if let text{info["value_utf16_length"]=(text as NSString).length;info["value_sha256"]=InputAccess.hash(text)}
        if let selection{info["selection_location"]=selection.location;info["selection_length"]=selection.length}
        return info
    }
    /// AX objects can be recreated by web editors. Re-identification needs the same window,
    /// identifier and geometry; never guess from just the process or role.
    func focusedInput()->AXUIElement?{
        guard AXIsProcessTrusted(),let pid,pid != getpid(),NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let original=element,
              let current=InputAccess.focused(pid:pid).flatMap({InputAccess.editable($0)})else{return nil}
        if let window{guard let currentWindow=InputAccess.value(current,kAXWindowAttribute),CFEqual(window,currentWindow)else{return nil}}
        if CFEqual(original,current){return current}
        guard !identifier.isEmpty,InputAccess.string(current,kAXIdentifierAttribute)==identifier,InputAccess.string(current,kAXRoleAttribute)==role,
              let geometry,let next=InputAccess.geometry(current),zip(geometry,next).allSatisfy({abs($0-$1)<1})else{return nil}
        return current
    }
    /// Read-only learning may follow an auto-growing editor. Paste checks above
    /// retain their stricter geometry/value/selection preconditions.
    func correctionInput()->AXUIElement?{
        guard AXIsProcessTrusted(),let pid,pid != getpid(),NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let original=element,
              let current=InputAccess.focused(pid:pid).flatMap({InputAccess.editable($0)})else{return nil}
        if let window{guard let next=InputAccess.value(current,kAXWindowAttribute),CFEqual(window,next)else{return nil}}
        if CFEqual(original,current){return current}
        guard window != nil,CorrectionTargetPolicy.matches(identifier:identifier,role:role,geometry:geometry,nextIdentifier:InputAccess.string(current,kAXIdentifierAttribute) ?? "",nextRole:InputAccess.string(current,kAXRoleAttribute) ?? "",nextGeometry:InputAccess.geometry(current))else{return nil}
        return current
    }
    func unchangedBeforeWrite(_ current:AXUIElement)->Bool{
        if let text,InputAccess.string(current,kAXValueAttribute) != text{return false}
        if let selection{guard let now=InputAccess.range(current),now.location==selection.location,now.length==selection.length else{return false}}
        return true
    }
}
enum CorrectionTargetPolicy {
    static func matches(identifier:String,role:String,geometry:[Double]?,nextIdentifier:String,nextRole:String,nextGeometry:[Double]?)->Bool{
        guard !identifier.isEmpty,identifier==nextIdentifier,role==nextRole,let a=geometry,let b=nextGeometry,a.count==4,b.count==4,(a+b).allSatisfy({$0.isFinite}),a[2]>0,a[3]>0,b[2]>0,b[3]>0 else{return false}
        // Same identifier/window/column; allow vertical growth around either edge.
        return abs(a[0]-b[0])<2 && abs(a[2]-b[2])<2 && max(a[1],b[1])<min(a[1]+a[3],b[1]+b[3])
    }
}
struct DeliveryReceipt {
    var state:String
    var message:String
    var audit:[String:Any]
    // Ephemeral evidence for correction detection, never serialized to history.
    var observedInsertionBaseline:String?=nil
    var resolvedTarget:PasteTarget?=nil
}
/// A missing start target can bind to the user's current cursor. An established
/// target cannot silently move to a different editor or overwrite a changed draft.
enum DeliveryTargetPolicy {
    static func mayAcquire(hadInput:Bool,currentInput:Bool,external:Bool)->Bool{!hadInput && currentInput && external}
    static func mayWait(reason:String,state:String,autoPaste:Bool)->Bool{
        reason=="input_not_focused" && ["clipboard","saved"].contains(state) && autoPaste
    }
    static let waitSeconds:Double=12
}
/// WeChat can have keyboard focus without exposing an AX editor. Use the window
/// and activity counters to scope a single keyboard paste to a hotkey dictation.
/// Neither window contents nor individual keystrokes are read or recorded.
struct WeChatPasteContext:Equatable {
    static let bundleID="com.tencent.xinWeChat"
    let pid:pid_t
    let windowID:CGWindowID
    let activationGeneration:Int
    let inputCounters:[UInt32]

    @MainActor static func capture(pid:pid_t,activationGeneration:Int)->Self?{
        guard let app=NSWorkspace.shared.frontmostApplication,app.processIdentifier==pid,app.bundleIdentifier==bundleID,
              let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]],
              let window=windows.first(where:{($0[kCGWindowLayer as String]as?Int)==0 && ($0[kCGWindowAlpha as String]as?Double ?? 0)>0}),
              (window[kCGWindowOwnerPID as String]as?pid_t)==pid,
              let id=window[kCGWindowNumber as String]as?CGWindowID,id != kCGNullWindowID else{return nil}
        let eventTypes:[CGEventType]=[.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown,.scrollWheel]
        let counters=eventTypes.map{CGEventSource.counterForEventType(.combinedSessionState,eventType:$0)}
        return Self(pid:pid,windowID:id,activationGeneration:activationGeneration,inputCounters:counters)
    }
}
/// Session-owned, one-shot late delivery. Clipboard changes, new jobs and timeout
/// invalidate it. No retry is permitted after a write was attempted.
struct PendingDeliveryLease {
    let id:UUID
    let deadline:Double
    let clipboardVersion:Int
    private(set) var consumed=false
    mutating func claim(id:UUID,now:Double,clipboardVersion:Int,inputAvailable:Bool)->Bool{
        guard !consumed,self.id==id,now<deadline,self.clipboardVersion==clipboardVersion else{consumed=true;return false}
        guard inputAvailable else{return false}
        consumed=true;return true
    }
}
enum DeliveryWritePlan:String {
    case keyboardPaste="keyboard_paste",selectedText="selected_text",unsupported
    static func choose(keepClipboard:Bool,clipboardUnchanged:Bool,eventPostingAllowed:Bool,selectedTextSettable:Bool)->Self{
        // A successful AX setter is not proof that a web editor committed it.
        // Prefer its normal paste event whenever the user's clipboard policy permits.
        if keepClipboard && clipboardUnchanged && eventPostingAllowed{return .keyboardPaste}
        return selectedTextSettable ? .selectedText:.unsupported
    }
}
enum DeliveryEvidence {
    static func alreadyAtCursor(value:String?,range:CFRange?,inserted:String)->Bool{
        guard !inserted.isEmpty,let value,let range,range.length==0 else{return false}
        let text=value as NSString,length=(inserted as NSString).length
        guard range.location>=length,range.location<=text.length else{return false}
        return text.substring(with:NSRange(location:range.location-length,length:length))==inserted
    }
    static func expected(before:String?,range:CFRange?,inserted:String)->String?{
        guard let before,let range,range.location>=0,range.length>=0,range.location<=(before as NSString).length,
              range.length<=(before as NSString).length-range.location else{return nil}
        return (before as NSString).replacingCharacters(in:NSRange(location:range.location,length:range.length),with:inserted)
    }
    static func equivalent(_ a:String,_ b:String)->Bool{a.replacingOccurrences(of:"\r\n",with:"\n")==b.replacingOccurrences(of:"\r\n",with:"\n")}
    static func verification(before:String?,observed:String,inserted:String,expected:String?,webPaste:Bool)->String?{
        if let expected,equivalent(observed,expected){return "exact_expected_value"}
        // Web editors expose paragraph terminators and sometimes stale selection ranges.
        // Require a changed value and a newly observed exact insertion, never setter success.
        guard webPaste,let before,!inserted.isEmpty else{return nil}
        func normalized(_ text:String)->String{text.replacingOccurrences(of:"\r\n",with:"\n").trimmingCharacters(in:.newlines)}
        let a=normalized(before),b=normalized(observed),needle=inserted.replacingOccurrences(of:"\r\n",with:"\n")
        guard a != b,b.contains(needle)else{return nil}
        let oldOccurrences=a.components(separatedBy:needle).count-1,newOccurrences=b.components(separatedBy:needle).count-1
        return newOccurrences>oldOccurrences ? "new_inserted_text_observed":nil
    }
}
/// Web editors can commit after the first AX read. Observe one write for up to
/// 1.8 s, returning early after two identical, proven insertion observations.
/// Never retry a paste merely because its readback was late or unavailable.
struct DeliveryReadbackProbe {
    static let pauses:[UInt64]=[0,35,45,70,110,170,240,330,400,400].map{$0*1_000_000}
    private(set) var consecutive=0
    private(set) var baseline:String?
    private(set) var evidence:String?
    private var previous:String?
    mutating func observe(_ value:String?,before:String?,inserted:String,expected:String?,webPaste:Bool)->Bool{
        guard let value,let proof=DeliveryEvidence.verification(before:before,observed:value,inserted:inserted,expected:expected,webPaste:webPaste)else{consecutive=0;previous=nil;return false}
        consecutive=previous.map{DeliveryEvidence.equivalent($0,value)} == true ? consecutive+1:1
        previous=value;baseline=value;evidence=proof
        return consecutive>=2
    }
}
@MainActor enum Delivery {
    @discardableResult static func copy(_ text:String)->Bool{NSPasteboard.general.clearContents();return NSPasteboard.general.setString(text,forType:.string)}
    private static func pasteEvents()->(CGEvent,CGEvent)?{
        guard let down=CGEvent(keyboardEventSource:nil,virtualKey:9,keyDown:true),
              let up=CGEvent(keyboardEventSource:nil,virtualKey:9,keyDown:false) else{return nil}
        down.flags = .maskCommand;up.flags = .maskCommand
        return (down,up)
    }
    static func deliver(_ text:String,target original:PasteTarget?,preferences:Preferences,activationGeneration:Int=0,stillCurrent:()->Bool) async ->DeliveryReceipt{
        let started=ProcessInfo.processInfo.systemUptime,eventPostingAllowed=CGPreflightPostEventAccess()
        var target=original
        var audit:[String:Any]=["version":7,"verified":false,"post_event_access":eventPostingAllowed]
        var currentFocus:PasteTarget?
        if let target{audit["capture"]=target.audit}
        if let original,original.element==nil{
            var current=PasteTarget.capture()
            currentFocus=current
            audit["current_focus"]=current.audit
            let sameWeChat=original.weChatContext==nil || (current.pid==original.pid && current.bundleID==original.bundleID)
            if sameWeChat,DeliveryTargetPolicy.mayAcquire(hadInput:false,currentInput:current.element != nil,external:current.pid != nil && current.pid != getpid()){
                current.clipboardVersion=original.clipboardVersion;target=current
                audit["target_resolution"]="acquired_current_focus"
            }
        }
        var observedInsertion:String?
        func receipt(_ state:String,_ message:String)->DeliveryReceipt{
            audit["total_seconds"]=ProcessInfo.processInfo.systemUptime-started
            return DeliveryReceipt(state:state,message:message,audit:audit,observedInsertionBaseline:observedInsertion,resolvedTarget:target)
        }
        guard !text.isEmpty else{audit["reason"]="empty_recognition";return receipt("empty","未识别到文字，录音已保留，可重试。")}
        let board=NSPasteboard.general
        let clipboardUnchanged=target.map{board.changeCount==$0.clipboardVersion} ?? false
        audit["clipboard_unchanged"]=clipboardUnchanged
        func preserve(_ reason:String)->DeliveryReceipt{
            audit["reason"]=reason
            let canPreserveClipboard=clipboardUnchanged && board.changeCount==target?.clipboardVersion
            audit["clipboard_unchanged"]=canPreserveClipboard
            if preferences.keepClipboard,canPreserveClipboard,copy(text){
                audit["copied"]=true
                return receipt("clipboard",reason=="input_not_focused" ? "结果已保存并复制，12秒内点击输入框可自动填入。":"未自动填入；结果已保存并复制，定位后可直接粘贴。")
            }
            return receipt("saved",canPreserveClipboard ? "未自动填入，结果已保存，可从历史复制。":"未自动填入，结果已保存；保留了你新复制的内容。")
        }
        guard stillCurrent()else{return receipt("saved","任务已停止，结果已保存。")}
        guard preferences.autoPaste else{return preserve("auto_paste_disabled")}
        guard let target,target.element != nil else{
            guard let context=target?.weChatContext else{return preserve("input_not_focused")}
            guard let currentFocus,currentFocus.pid==context.pid,currentFocus.focusedOwner==nil,
                  context==WeChatPasteContext.capture(pid:context.pid,activationGeneration:activationGeneration)else{return preserve("wechat_context_changed")}
            guard preferences.keepClipboard,clipboardUnchanged,eventPostingAllowed,let (down,up)=pasteEvents(),
                  stillCurrent(),board.changeCount==target?.clipboardVersion,copy(text)else{return preserve("wechat_paste_unavailable")}
            audit["copied"]=true
            let preparedClipboard=board.changeCount
            let contextStable=context==WeChatPasteContext.capture(pid:context.pid,activationGeneration:activationGeneration)
            guard board.changeCount==preparedClipboard,board.string(forType:.string)==text else{return preserve("wechat_clipboard_changed_before_post")}
            guard contextStable,NSWorkspace.shared.frontmostApplication?.processIdentifier==context.pid else{
                audit["reason"]="wechat_context_changed_before_post"
                return receipt("clipboard","未自动填入；结果已保存并复制，定位后可直接粘贴。")
            }
            down.post(tap:.cghidEventTap);up.post(tap:.cghidEventTap)
            audit["method"]="wechat_keyboard_paste";audit["reason"]="write_sent_but_unverified"
            return receipt("unverified","已向微信尝试粘贴，请核对输入框。")
        }
        guard let input=target.focusedInput(),target.unchangedBeforeWrite(input)else{return preserve("input_missing_or_changed")}
        let before=InputAccess.string(input,kAXValueAttribute),range=InputAccess.range(input)
        let expected=DeliveryEvidence.expected(before:before,range:range,inserted:text)
        audit["expected_value_available"]=expected != nil
        // AXSelectedText can report success while a web editor drops the change.
        // Normal keyboard paste notifies the web editor's own input handlers.
        let plan=DeliveryWritePlan.choose(keepClipboard:preferences.keepClipboard,clipboardUnchanged:clipboardUnchanged,eventPostingAllowed:eventPostingAllowed,selectedTextSettable:InputAccess.settable(input,kAXSelectedTextAttribute))
        audit["write_plan"]=plan.rawValue
        var method="",sent=false,apiSuccess=false
        if plan == .keyboardPaste {
            guard stillCurrent(),let current=target.focusedInput(),target.unchangedBeforeWrite(current),
                  board.changeCount==target.clipboardVersion,copy(text)else{return preserve("paste_precondition_changed")}
            guard let (down,up)=pasteEvents()else{return preserve("paste_event_unavailable")}
            down.post(tap:.cghidEventTap);up.post(tap:.cghidEventTap);method="keyboard_paste";sent=true
        }else if plan == .selectedText {
            apiSuccess=AXUIElementSetAttributeValue(input,kAXSelectedTextAttribute as CFString,text as CFString) == .success
            method="selected_text";sent=apiSuccess
        }
        audit["method"]=method;audit["ax_set_success"]=apiSuccess
        audit["first_write_sent_seconds"]=ProcessInfo.processInfo.systemUptime-started
        var writeAttempts:[[String:Any]]=[]
        func verifyWrite(webPaste:Bool)async->Bool{
            var probe=DeliveryReadbackProbe(),attempts=0
            let start=ProcessInfo.processInfo.systemUptime
            defer{
                writeAttempts.append(["method":audit["method"]as?String ?? method,"readback_attempts":attempts,"readback_seconds":ProcessInfo.processInfo.systemUptime-start,"verified":probe.consecutive>=2])
                audit["write_attempts"]=writeAttempts
            }
            for pause in DeliveryReadbackProbe.pauses{
                if pause>0{try? await Task.sleep(nanoseconds:pause)}
                guard stillCurrent(),!Task.isCancelled else{return false}
                attempts+=1
                let current=target.focusedInput(),value=current.flatMap{InputAccess.string($0,kAXValueAttribute)}
                if let value{audit["observed_value_utf16_length"]=(value as NSString).length;audit["observed_value_sha256"]=InputAccess.hash(value)}
                let verified=probe.observe(value,before:before,inserted:text,expected:expected,webPaste:webPaste)
                if let baseline=probe.baseline{observedInsertion=baseline}
                if let evidence=probe.evidence{audit["verification_evidence"]=evidence}
                audit["readback_attempts"]=attempts;audit["readback_seconds"]=ProcessInfo.processInfo.systemUptime-start
                if verified{return true}
            }
            return false
        }
        if sent {
            if await verifyWrite(webPaste:method=="keyboard_paste"){
                audit["verified"]=true
                if method=="selected_text",preferences.keepClipboard,clipboardUnchanged,board.changeCount==target.clipboardVersion{_ = copy(text)}
                return receipt("verified","已填入输入位置并核对，结果已保存。")
            }
        }
        // Retry exactly once only when the original value AND selection prove no insertion.
        // An unreadable editor must never receive a speculative second paste.
        if method != "keyboard_paste",eventPostingAllowed,preferences.keepClipboard,clipboardUnchanged,board.changeCount==target.clipboardVersion,stillCurrent(),let before,let range,
           let current=target.focusedInput(),InputAccess.string(current,kAXValueAttribute)==before,
           let selection=InputAccess.range(current),selection.location==range.location,selection.length==range.length {
            guard copy(text),let (down,up)=pasteEvents()else{return preserve("fallback_unavailable")}
            down.post(tap:.cghidEventTap);up.post(tap:.cghidEventTap)
            audit["method"]="keyboard_paste_fallback"
            if await verifyWrite(webPaste:true){audit["verified"]=true;return receipt("verified","已填入输入位置并核对，结果已保存。")}
            sent=true
        }
        guard stillCurrent()else{return receipt("saved","任务已停止，结果已保留，请检查输入框。")}
        if sent{audit["reason"]="write_sent_but_unverified";return receipt("unverified","已尝试写入，但未能确认输入框已收到；结果已保留，请核对或手动复制。")}
        return preserve("no_supported_write_method")
    }
}
