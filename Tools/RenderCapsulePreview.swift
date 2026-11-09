import AppKit
import Foundation

/// Off-screen render of the actual app renderer. Levels are explicitly simulated.
@main struct RenderCapsulePreview {
    static func main()throws{
        _=NSApplication.shared
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let width=360,height=144,scale=2
        func frame(_ index:Int,state:CapsuleMotionState,time:Double,level:Double)throws{
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width*scale,pixelsHigh:height*scale,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            rep.size=NSSize(width:width,height:height)
            let graphics=NSGraphicsContext(bitmapImageRep:rep)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
            let c=graphics.cgContext
            c.setFillColor(NSColor(srgbRed:0.19,green:0.20,blue:0.23,alpha:1).cgColor);c.fill(CGRect(x:0,y:0,width:width,height:height))
            let bounds=CGRect(x:96,y:71,width:168,height:36)
            CapsuleDotRenderer.draw(c,bounds:bounds,state:state,level:level,time:time,reduced:false)
            let text=NSAttributedString(string:state.compactTitle,attributes:[.font:NSFont.systemFont(ofSize:10.5,weight:.medium),.foregroundColor:NSColor.white.withAlphaComponent(0.94)])
            text.draw(at:NSPoint(x:bounds.minX+12,y:bounds.midY-text.size().height/2))
            for (symbol,x,size) in [(state.symbol ?? (state == .recording ? "stop.fill":"ellipsis"),148.0,10.0)]{
                if let image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:size,weight:.regular)),let mask=image.cgImage(forProposedRect:nil,context:graphics,hints:nil){
                    let target=CGRect(x:bounds.minX+x-image.size.width/2,y:bounds.midY-image.size.height/2,width:image.size.width,height:image.size.height)
                    c.saveGState();c.clip(to:target,mask:mask);c.setFillColor(NSColor.white.cgColor);c.fill(target);c.restoreGState()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(String(format:"frame-%04d.png",index)))
        }
        for index in 0..<720{
            let time=Double(index)/60,state:CapsuleMotionState=time<0.6 ? .preparing:time<4.6 ? .recording:time<6.6 ? .recognizing:time<8.6 ? .cleaning:time<10.6 ? .translating:.filled
            let level=0.12+0.68*pow(max(0,sin(time*4.2)*0.5+0.5),2)
            try frame(index,state:state,time:time,level:level)
        }
        print("Exported720 native-renderer preview frames; simulated level input, not a microphone test.")
    }
}
