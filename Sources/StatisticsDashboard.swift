import SwiftUI

enum ActivityColors {
    static let card=DianyuDesign.adaptive("ActivityCard",dark:0x282A2C,light:0xFFFFFF)
    static let empty=DianyuDesign.adaptive("ActivityEmpty",dark:0x33363B,light:0xF5F6F8)
    static let hatch=DianyuDesign.adaptive("ActivityHatch",dark:0x45494F,light:0xE7E9EE)
    static let future=DianyuDesign.adaptive("ActivityFuture",dark:0x41454B,light:0xECEEF2)
    static let levels:[Color]=[
        empty,
        DianyuDesign.adaptive("ActivityOne",dark:0x263759,light:0xEAF0FF),
        DianyuDesign.adaptive("ActivityTwo",dark:0x36578D,light:0xC4D2FF),
        DianyuDesign.adaptive("ActivityThree",dark:0x547FD3,light:0x98B3FF),
        DianyuDesign.adaptive("ActivityFour",dark:0x7A9FFF,light:0x356AF4)
    ]
}
private struct ActivityHatching:Shape {
    func path(in rect:CGRect)->Path{
        var path=Path()
        for x in stride(from:-rect.height,through:rect.width,by:5){path.move(to:CGPoint(x:x,y:rect.maxY));path.addLine(to:CGPoint(x:x+rect.height,y:rect.minY))}
        return path
    }
}
struct StatisticsDashboard:View {
    let records:[SessionRecord]
    var now=Date()
    var body:some View{ScrollView{StatisticsContent(records:records,now:now)}}
}
/// Shared content keeps preview rendering identical to the live scroll page.
struct StatisticsContent:View {
    let records:[SessionRecord]
    var now=Date()
    @UIState private var periodOffset=0
    var body:some View{
        let totals=Metrics.totals(records),streak=Metrics.streak(records,now:now)
        let activity=StatisticsActivity(records:records,now:now,offset:periodOffset)
        VStack(alignment:.leading,spacing:16){
                HStack(spacing:16){
                    overview("平均口述速度"){
                        number("\(totals.wpm)");unit("字词 / 分钟")
                    }
                    overview("总口述时间"){
                        let minutes=Int(max(0,totals.seconds)/60)
                        if minutes>=60{number("\(minutes/60)");unit("小时")}
                        number("\(minutes%60)");unit("分钟")
                    }
                }
                VStack(alignment:.leading,spacing:24){
                    HStack(alignment:.top,spacing:20){
                        activityMetric("活跃天数",value:activity.activeDays)
                        activityMetric("当前连续天数",value:streak.current)
                        activityMetric("最长连续天数",value:streak.longest)
                    }
                    ActivityCalendarView(activity:activity,previous:{periodOffset-=1},next:{periodOffset+=1})
                    if totals.sessions==0{Text("还没有听写记录，完成一次语音输入后会显示在这里。").font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}
                }.padding(22).background(ActivityColors.card,in:RoundedRectangle(cornerRadius:20))
                HStack(alignment:.firstTextBaseline,spacing:22){
                    summary("累计输入",value:"\(totals.words.formatted()) 字词")
                    summary("听写次数",value:"\(totals.sessions.formatted()) 次")
                    Spacer(minLength:0)
                    let completed=records.filter{$0.counted && $0.processingSeconds>0}
                    if !completed.isEmpty{summary("平均处理",value:String(format:"%.2f 秒",completed.reduce(0){$0+$1.processingSeconds}/Double(completed.count)))}
                }.padding(.horizontal,4).padding(.top,2)
                Text("中文按字计，英文与数字按词计。仅统计成功的麦克风输入；重试不重复累计，文本自测和文件导入不计入。全部记录保存在本机。")
                    .font(.system(size:11)).foregroundStyle(DianyuDesign.secondary).fixedSize(horizontal:false,vertical:true).lineSpacing(3).padding(.horizontal,4)
        }.padding(.leading,20).padding(.trailing,24).padding(.bottom,24)
    }
    private func number(_ value:String)->some View{Text(value).font(.system(size:34,weight:.semibold)).tracking(-0.8).monospacedDigit()}
    private func unit(_ value:String)->some View{Text(value).font(.system(size:12,weight:.semibold)).padding(.trailing,2)}
    private func overview<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View{
        VStack(alignment:.leading,spacing:11){HStack(alignment:.firstTextBaseline,spacing:5,content:content).lineLimit(1).minimumScaleFactor(0.75);Text(title).font(.system(size:13)).foregroundStyle(DianyuDesign.secondary)}
            .frame(maxWidth:.infinity,alignment:.leading).padding(22).background(ActivityColors.card,in:RoundedRectangle(cornerRadius:20)).accessibilityElement(children:.combine)
    }
    private func activityMetric(_ title:String,value:Int)->some View{
        VStack(alignment:.leading,spacing:9){HStack(alignment:.firstTextBaseline,spacing:5){Text("\(value)").font(.system(size:28,weight:.semibold)).monospacedDigit();Text("天").font(.system(size:12,weight:.medium))};Text(title).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary)}.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private func summary(_ title:String,value:String)->some View{VStack(alignment:.leading,spacing:5){Text(value).font(.system(size:13,weight:.medium)).monospacedDigit();Text(title).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)}.accessibilityElement(children:.combine)}
}
private struct ActivityCalendarView:View {
    let activity:StatisticsActivity
    let previous:()->Void,next:()->Void
    var body:some View{
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:8){
                Text("听写活动").font(.system(size:12,weight:.medium));Spacer()
                Text(activity.rangeLabel).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
                navigation("上一段听写活动",symbol:"chevron.left",action:previous).disabled(!activity.canGoBack)
                navigation("下一段听写活动",symbol:"chevron.right",action:next).disabled(!activity.canGoForward)
            }
            HStack(alignment:.top,spacing:10){
                VStack(spacing:0){ForEach(Array(["日","一","二","三","四","五","六"].enumerated()),id:\.offset){_,label in Text(label).font(.system(size:10)).foregroundStyle(DianyuDesign.secondary).frame(maxHeight:.infinity)}}.frame(width:12)
                ActivityHeatmapLayout{ForEach(activity.days){day in
                    ActivityDayCell(day:day).help(dayDescription(day)).accessibilityLabel(dayDescription(day))
                }}
            }.fixedSize(horizontal:false,vertical:true)
            HStack(spacing:10){
                Color.clear.frame(width:12,height:20)
                GeometryReader{proxy in
                    let grid=ActivityGridMetrics(width:proxy.size.width),labelWidth:CGFloat=32
                    ForEach(activity.months){month in
                        Text(month.title).font(.system(size:10)).foregroundStyle(DianyuDesign.secondary).frame(width:labelWidth,alignment:.leading)
                            .offset(x:min(grid.frame(month.column*7).minX,max(0,proxy.size.width-labelWidth)),y:2)
                    }
                }.frame(height:20)
            }
            HStack(spacing:6){
                Text("更少").padding(.trailing,3)
                ForEach(1..<5,id:\.self){level in RoundedRectangle(cornerRadius:3).fill(ActivityColors.levels[level]).frame(width:12,height:12).accessibilityHidden(true)}
                Text("更多").padding(.leading,3)
                Spacer(minLength:4)
                ActivityHatching().stroke(ActivityColors.hatch,lineWidth:1.2).frame(width:12,height:12).clipShape(RoundedRectangle(cornerRadius:3)).accessibilityHidden(true)
                Text("早于首条记录")
            }.font(.system(size:10)).foregroundStyle(DianyuDesign.secondary).accessibilityElement(children:.combine)
        }
    }
    private func navigation(_ label:String,symbol:String,action:@escaping()->Void)->some View{
        Button(action:action){Image(systemName:symbol).font(.system(size:11,weight:.semibold)).frame(width:20,height:24).contentShape(Rectangle())}.buttonStyle(FlatButtonStyle(kind:.quiet)).accessibilityLabel(label).help(label)
    }
    private func dayDescription(_ day:StatisticsActivity.Day)->String{
        let text=day.date.formatted(.dateTime.year().month().day().weekday())
        switch day.kind{case .future:return text+"，未来日期";case .beforeHistory:return text+"，早于首条听写记录";default:return text+"，\(day.count) 次听写"}
    }
}
private struct ActivityDayCell:View {
    let day:StatisticsActivity.Day
    var body:some View{
        GeometryReader{proxy in
            let radius=min(5,proxy.size.width*0.25)
            let shape=RoundedRectangle(cornerRadius:radius)
            switch day.kind{
            case .beforeHistory:ActivityHatching().stroke(ActivityColors.hatch,lineWidth:1.2).clipShape(shape)
            case .future:shape.strokeBorder(ActivityColors.future,lineWidth:1)
            case .empty:shape.fill(ActivityColors.empty)
            case .activity:shape.fill(ActivityColors.levels[day.level])
            }
        }
    }
}
