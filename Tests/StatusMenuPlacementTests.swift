import AppKit

@main struct StatusMenuPlacementTests {
    static func main(){
        var count=0
        func check(_ value:Bool,_ name:String){precondition(value,name);count+=1}
        let cases:[(CGRect,CGRect)]=[
            (CGRect(x:0,y:30,width:1440,height:840),CGRect(x:800,y:870,width:24,height:30)),
            (CGRect(x:-1920,y:40,width:1920,height:1040),CGRect(x:-20,y:1080,width:24,height:25)),
            (CGRect(x:1440,y:-900,width:1280,height:870),CGRect(x:1450,y:-30,width:24,height:30)),
            (CGRect(x:0,y:0,width:640,height:480),CGRect(x:630,y:480,width:24,height:25))
        ]
        let size=CGSize(width:284,height:420)
        for (visible,button)in cases{
            let origin=StatusMenuPlacement.topLeft(button:button,menu:size,visible:visible)
            check(origin.x>=visible.minX+6 && origin.x+size.width<=visible.maxX-6,"Menu fits the selected display before opening")
            check(origin.y<=visible.maxY-6 && origin.y-size.height>=visible.minY+6,"Menu fits vertically without a late native clamp")
            check(origin==StatusMenuPlacement.topLeft(button:button,menu:size,visible:visible),"Repeated openings have identical screen anchors")
        }
        let first=StatusMenuPlacement.topLeft(button:cases[0].1,menu:size,visible:cases[0].0)
        check(first.x==800,"Ordinary menu retains the icon's left alignment")
        let edge=StatusMenuPlacement.topLeft(button:cases[1].1,menu:size,visible:cases[1].0)
        check(edge.x == -290,"Right edge is clamped before tracking, including negative display coordinates")
        let oversized=StatusMenuPlacement.topLeft(button:CGRect(x:0,y:200,width:24,height:30),menu:CGSize(width:800,height:900),visible:CGRect(x:0,y:0,width:320,height:200))
        check(oversized.x==6 && oversized.y==194,"Oversized native scrolling menus still receive a valid visible anchor")
        print("Status menu placement checks passed:",count)
    }
}
