import AppKit

@main struct StatisticsScrollTests {
    @MainActor static func main(){
        _=NSApplication.shared
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:822,height:640),
                            styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        let scroll=StatisticsScrollView(content:StatisticsContent(records:[]))
        window.contentView=scroll

        for size in [NSSize(width:822,height:400),NSSize(width:822,height:640),
                     NSSize(width:920,height:640),NSSize(width:822,height:900)]{
            window.setContentSize(size)
            scroll.layoutSubtreeIfNeeded()
            scroll.layout()
            let document=scroll.documentView!.frame.size
            precondition(scroll.scrollerStyle == .overlay)
            precondition(scroll.contentSize.width==size.width && document.width==size.width)
            precondition(document.height>=scroll.contentSize.height && document.height>=550)
            scroll.layout()
            precondition(scroll.documentView!.frame.size==document)
        }
        print("Statistics scroll sizing remains stable across four window sizes")
    }
}
