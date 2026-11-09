import AppKit
import SwiftUI

/// Uses the shipping SwiftUI dashboard with in-memory simulated records only.
/// No AppState, microphone, permissions, preferences or LibraryStore is created.
@main struct RenderStatisticsPreview {
    @MainActor static func main()throws{
        _=NSApplication.shared
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone.current
        let now=cal.date(from:DateComponents(year:2026,month:11,day:6,hour:12))!
        var records:[SessionRecord]=[]
        for day in -155...0{
            let count=day%11==0 ? 12:day%7==0 ? 7:day%4==0 ? 4:day%5==0 ? 0:1
            for _ in 0..<count{
                var r=SessionRecord();r.created=cal.date(byAdding:.day,value:day,to:now)!;r.finished=r.created;r.status="completed";r.raw="请检查设计文件，保留这个版本。";r.cleaned=r.raw;r.output=r.raw;r.duration=5.2;r.processingSeconds=0.7;records.append(r)
            }
        }
        for (name,width,scheme,empty) in [("light-compact",CGFloat(650),ColorScheme.light,false),("dark-compact",650,.dark,false),("light-wide",960,.light,false),("dark-empty",650,.dark,true)]{
            NSApp.appearance=NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)
            let view=StatisticsContent(records:empty ? []:records,now:now).foregroundStyle(DianyuDesign.primary).frame(width:width).fixedSize(horizontal:false,vertical:true).padding(.vertical,20).background(DianyuDesign.page).environment(\.colorScheme,scheme)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            guard let image=renderer.cgImage else{throw NSError(domain:"StatisticsPreview",code:1)}
            let bitmap=NSBitmapImageRep(cgImage:image)
            try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name+".png"))
        }
        print("Rendered shipping dashboard in light/dark/compact/wide/empty configurations; simulated records, not production screenshots.")
    }
}
