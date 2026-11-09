import AppKit
import SwiftUI

/// Hidden, test-owned window. No user-window automation or system preference changes.
@main struct WindowChromeTests {
    static func main(){
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1360,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let original=[NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton].map{window.standardWindowButton($0)!}
        let host=TrafficLightHost(frame:NSRect(x:24,y:842,width:200,height:34));window.contentView!.addSubview(host);host.adoptButtons()
        for (i,button)in host.buttons.enumerated(){
            let reference=NSWindow.standardWindowButton([NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton][i],for:window.styleMask)!
            check(type(of:button)==type(of:reference),"Uses the native AppKit factory button class")
            check(button.superview === host && button.target === host && button.action != nil,"Native control is inside navigation and routes to this window")
            check(host.bounds.contains(button.frame),"Whole button lies within navigation control row")
            let rect=window.contentView!.convert(button.bounds,from:button)
            check(NSRect(x:12,y:12,width:224,height:876).contains(rect),"Whole button lies within floating sidebar")
        }
        host.setFrameSize(NSSize(width:200,height:42));host.layoutSubtreeIfNeeded()
        check(host.buttons.allSatisfy{host.bounds.contains($0.frame) && !$0.isHidden},"Controls remain visible and inside after layout")
        host.restoreButtons();check(original.allSatisfy{!$0.isHidden},"Detaching restores original native visibility")
        host.adoptButtons();check(host.buttons.count==3 && original.allSatisfy{$0.isHidden},"Reattaching gives one visible native control set")
        let glass=NavigationGlassHost(content:Text("Local test"));glass.frame=NSRect(x:0,y:0,width:224,height:650);window.contentView!.addSubview(glass);glass.layoutSubtreeIfNeeded()
        if #available(macOS 26.0,*),!NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency{check(glass.usesSystemGlass,"Real NSGlassEffectView on supported systems")}
        check(glass.hosting.frame.size==glass.bounds.size,"Content follows glass bounds")
        for (name,color)in [(NSAppearance.Name.darkAqua,DianyuDesign.page),(.aqua,DianyuDesign.page)]{
            let appearance=NSAppearance(named:name)!
            appearance.performAsCurrentDrawingAppearance{let rgb=NSColor(color).usingColorSpace(.sRGB)!;check(rgb.alphaComponent==1,"Content surface is opaque in both appearances")}
        }
        print("Window chrome checks passed:",checks)
        host.restoreButtons()
    }
}
