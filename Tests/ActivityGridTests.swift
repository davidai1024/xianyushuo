import AppKit
import SwiftUI

@main struct ActivityGridTests {
    static func main(){
        var checks=0
        func check(_ value:Bool,_ name:String){precondition(value,name);checks+=1}
        for width in [CGFloat(400),600,850,1100]{
            let grid=ActivityGridMetrics(width:width)
            check(abs(grid.frame(181).maxX-width)<0.001,"Last week reaches the full available right edge")
            check(grid.frame(0).minX==0 && grid.frame(0).minY==0,"First day starts at grid origin")
            check(abs(grid.frame(181).maxY-grid.height)<0.001,"Last day reaches bottom edge")
            check(width<600 || grid.cell>13,"Wide containers grow cells instead of leaving half the card empty")
            for index in [0,6,7,90,175,181]{
                let frame=grid.frame(index)
                check(abs(frame.width-frame.height)<0.001,"Activity cells stay square")
                check(CGRect(x:0,y:0,width:width+0.001,height:grid.height+0.001).contains(frame),"Activity cells never overflow their card")
            }
        }
        print("Responsive activity-grid checks passed:",checks)
    }
}
