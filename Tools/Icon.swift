import AppKit
import ImageIO

let folder=URL(fileURLWithPath:CommandLine.arguments[1])
let source=URL(fileURLWithPath:CommandLine.arguments[2])
let resources=source.deletingLastPathComponent(),supplied=resources.appendingPathComponent("Branding")
let files=FileManager.default
try files.createDirectory(at:folder,withIntermediateDirectories:true)
func replace(_ input:URL,_ output:URL)throws{if files.fileExists(atPath:output.path){try files.removeItem(at:output)};try files.copyItem(at:input,to:output)}
// Keep the user's finished Dock artwork and their size-specific exports exact.
let icon=supplied.appendingPathComponent("AppIcon.icns")
guard NSImage(contentsOf:icon) != nil else{fatalError("Missing supplied ICNS")}
try replace(icon,resources.appendingPathComponent("AppIcon.icns"))
for file in try files.contentsOfDirectory(at:supplied.appendingPathComponent("AppIcon.iconset"),includingPropertiesForKeys:nil)where file.pathExtension=="png"{try replace(file,folder.appendingPathComponent(file.lastPathComponent))}
// Luminance-to-alpha is only a mechanical template conversion. The supplied
// silhouette and dark fish-shaped hole are retained; no shape is re-drawn.
guard let image=NSImage(contentsOf:supplied.appendingPathComponent("SourceMark.png")),let cg=image.cgImage(forProposedRect:nil,context:nil,hints:nil)else{fatalError("Missing supplied mark")}
let width=cg.width,height=cg.height,space=CGColorSpaceCreateDeviceRGB()
let pixels=UnsafeMutablePointer<UInt8>.allocate(capacity:width*height*4);defer{pixels.deallocate()}
guard let context=CGContext(data:pixels,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)else{fatalError("Cannot read supplied mark")}
context.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
var minX=width,minY=height,maxX=0,maxY=0
for y in 0..<height{for x in 0..<width{
 let i=(y*width+x)*4,alpha=Double(pixels[i+3])/255
 let light=alpha>0 ? (0.2126*Double(pixels[i])+0.7152*Double(pixels[i+1])+0.0722*Double(pixels[i+2]))/(255*alpha):0
 if light>0.3 && alpha>0.5{minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)}
 let edge=min(1,max(0,(light-0.08)/0.84)),smooth=edge*edge*(3-2*edge)
 pixels[i]=0;pixels[i+1]=0;pixels[i+2]=0;pixels[i+3]=UInt8((alpha*smooth*255).rounded())
}}
guard maxX>minX,maxY>minY else{fatalError("Empty supplied mark")}
let padding=max(12,Int(Double(max(maxX-minX,maxY-minY))*0.035))
let side=min(min(width,height),max(maxX-minX+1,maxY-minY+1)+padding*2)
let crop=CGRect(x:max(0,min(width-side,(minX+maxX+1-side)/2)),y:max(0,min(height-side,(minY+maxY+1-side)/2)),width:side,height:side)
guard let mask=context.makeImage()?.cropping(to:crop)else{fatalError("Cannot extract supplied silhouette")}
try NSBitmapImageRep(cgImage:mask).representation(using:.png,properties:[:])!.write(to:resources.appendingPathComponent("BrandMark.png"))
for (name,size)in [("MenuBarIcon.png",18),("MenuBarIcon@2x.png",36)]{
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let graphics=NSGraphicsContext(bitmapImageRep:bitmap)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics;graphics.imageInterpolation = .high
 let mark=NSImage(cgImage:mask,size:NSSize(width:side,height:side));mark.draw(in:NSRect(x:0,y:0,width:size,height:size),from:.zero,operation:.sourceOver,fraction:1)
 NSGraphicsContext.restoreGraphicsState()
 try bitmap.representation(using:.png,properties:[:])!.write(to:resources.appendingPathComponent(name))
}
print("Copied supplied Dock ICNS exactly; derived transparent brand and menu templates.")
