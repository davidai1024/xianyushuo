import AppKit
import Foundation

/// Own, undisplayed view only. No OS input events, hotkeys, user settings or permissions.
@main struct ShortcutFieldTests {
    static func main(){
        _=NSApplication.shared
        var checks=0
        func check(_ ok:Bool,_ label:String){precondition(ok,label);checks+=1}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let field=ShortcutField(frame:NSRect(x:20,y:20,width:116,height:32));window.contentView?.addSubview(field)
        var begins=0,ends=0,saved:[KeyBinding]=[],preview:[String]=[]
        field.binding=KeyBinding();field.begin={begins+=1};field.end={ends+=1};field.preview={preview=$0};field.commit={saved.append($0);return true}
        func event(_ type:NSEvent.EventType,_ code:UInt16,_ flags:NSEvent.ModifierFlags,_ chars:String)->NSEvent{
            NSEvent.keyEvent(with:type,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:chars,charactersIgnoringModifiers:chars,isARepeat:false,keyCode:code)!
        }
        func send(_ type:NSEvent.EventType,_ code:UInt16,_ flags:NSEvent.ModifierFlags,_ chars:String){_=field.performKeyEquivalent(with:event(type,code,flags,chars))}
        field.startEditing();check(field.editing && begins==1,"Inline recording starts")
        check(field.focusRingType == .none && !(field as NSView is NSButton),"Single surface without NSButtonCell/focus-ring overlap")
        send(.keyDown,2,[.control,.shift],"D");check(saved.isEmpty && preview==["⌃","⇧","D"],"Live preview contains only held new keys; save waits for release")
        send(.keyUp,2,[.control,.shift],"D");check(saved.count==1 && !field.editing && ends==1,"Key-up commits exactly once and releases capture")
        let original=field.binding;field.startEditing();send(.keyDown,0,[],"a");check(field.editing && saved.count==1,"Bare letter gives guidance and cannot save")
        send(.keyDown,53,[],"\u{1b}");check(!field.editing && field.binding==original && saved.count==1,"Escape preserves old binding")
        field.startEditing();NotificationCenter.default.post(name:NSWindow.didResignKeyNotification,object:window)
        check(!field.editing && field.binding==original,"Window focus loss cancels without committing")
        field.startEditing();NotificationCenter.default.post(name:NSApplication.didResignActiveNotification,object:NSApplication.shared)
        check(!field.editing,"Application switch cancels recording")
        field.startEditing();_=field.resignFirstResponder();check(!field.editing,"Outside focus cancels recording")
        field.startEditing();field.viewWillMove(toWindow:nil);check(!field.editing,"Page/view removal cancels and removes monitors")
        field.commit={_ in false};field.startEditing();send(.keyDown,2,[.control,.shift],"D");send(.keyUp,2,[.control,.shift],"D")
        check(field.editing && field.binding==original,"Conflict rejection stays editable and preserves old binding")
        field.cancelEditing();check(begins==ends,"Every capture pause has a matching resume")
        for dark in [false,true]{
            field.appearance=NSAppearance(named:dark ? .darkAqua:.aqua);field.needsDisplay=true
            if let bitmap=field.bitmapImageRepForCachingDisplay(in:field.bounds){field.appearance!.performAsCurrentDrawingAppearance{field.cacheDisplay(in:field.bounds,to:bitmap)};check(bitmap.pixelsWide>0,"Control renders in \(dark ? "dark":"light") appearance")}
            else{check(false,"Missing control bitmap")}
        }
        print("Shortcut field lifecycle checks passed:",checks)
    }
}
