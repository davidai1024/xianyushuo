import AppKit

enum StatusMenuPlacement {
    static let minimumWidth:CGFloat=284
    /// NSMenu's nil-item popup anchors its content's top-left. Compute the point
    /// in screen coordinates before converting it to the status button's view.
    /// Clamp before tracking instead of letting it slide
    /// sideways after the first layout near a screen edge.
    static func topLeft(button:CGRect,menu:CGSize,visible:CGRect)->CGPoint{
        let margin:CGFloat=6,gap:CGFloat=3
        let width=min(max(0,menu.width),max(0,visible.width-2*margin))
        let height=min(max(0,menu.height),max(0,visible.height-2*margin))
        let left=visible.minX+margin,right=max(left,visible.maxX-margin-width)
        let bottom=visible.minY+margin+height,top=max(bottom,visible.maxY-margin)
        return CGPoint(x:min(right,max(left,button.minX)),y:min(top,max(bottom,button.minY-gap)))
    }
}
