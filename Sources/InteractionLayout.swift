import AppKit
import SwiftUI

/// Mouse selection is not keyboard focus. Do not leave a focus box after clicks.
final class KeyboardFocusFeedback:ObservableObject {
    static let shared=KeyboardFocusFeedback()
    @Published private(set) var visible=false
    private var monitor:Any?
    func start(){
        guard monitor==nil else{return}
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.leftMouseDown,.rightMouseDown,.otherMouseDown]){[weak self] event in
            guard let self else{return event}
            if event.type == .keyDown {
                if !self.visible,[48,123,124,125,126,115,119].contains(event.keyCode){self.visible=true}
            }else if self.visible{self.visible=false}
            return event
        }
    }
    deinit{if let monitor{NSEvent.removeMonitor(monitor)}}
}

/// Seven days per column; every available horizontal point belongs to the grid.
struct ActivityGridMetrics {
    let width:CGFloat
    let columns=26,rows=7
    var gap:CGFloat{min(7,max(3,width/95))}
    var cell:CGFloat{max(1,(width-CGFloat(columns-1)*gap)/CGFloat(columns))}
    var height:CGFloat{CGFloat(rows)*cell+CGFloat(rows-1)*gap}
    func frame(_ index:Int)->CGRect{
        CGRect(x:CGFloat(index/rows)*(cell+gap),y:CGFloat(index%rows)*(cell+gap),width:cell,height:cell)
    }
}
