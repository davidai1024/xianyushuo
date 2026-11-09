import AppKit
import SwiftUI

@main struct DesignLayoutTests {
    static func main(){
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        for word in [String(repeating:"词",count:80),String(repeating:"W",count:80)]{
            let short=NSHostingView(rootView:VocabularyWordLabel(word:"word").frame(width:220))
            let long=NSHostingView(rootView:VocabularyWordLabel(word:word).frame(width:220))
            check(long.fittingSize.height>short.fittingSize.height,"80-codepoint word wraps instead of truncating")
            check(long.fittingSize.width<=221,"Long word cannot widen the content column")
        }
        func luminance(_ color:NSColor)->Double{
            let c=color.usingColorSpace(.sRGB)!
            func linear(_ n:Double)->Double{n<=0.04045 ? n/12.92:pow((n+0.055)/1.055,2.4)}
            return 0.2126*linear(c.redComponent)+0.7152*linear(c.greenComponent)+0.0722*linear(c.blueComponent)
        }
        func contrast(_ a:NSColor,_ b:NSColor)->Double{let x=luminance(a),y=luminance(b);return(max(x,y)+0.05)/(min(x,y)+0.05)}
        let dark=NSAppearance(named:.darkAqua)!
        dark.performAsCurrentDrawingAppearance{
            for color in [DianyuDesign.primary,DianyuDesign.secondary,DianyuDesign.tertiary]{for background in [DianyuDesign.page,DianyuDesign.group]{check(contrast(NSColor(color),NSColor(background))>=4.5,"Readable dark-content text contrast")}}
            check(contrast(NSColor(DianyuDesign.accent),NSColor(DianyuDesign.accentInk))>=4.5,"Primary action text contrast")
            check(contrast(NSColor(DianyuDesign.onGlassMuted),NSColor(srgbRed:81/255,green:81/255,blue:81/255,alpha:1))>=4.5,"Muted navigation text against observed dark glass sample")
        }
        print("Design layout/contrast checks passed:",checks)
    }
}
