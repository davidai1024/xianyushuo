import SwiftUI
import AppKit

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
        for x in stride(from:-rect.height,through:rect.width,by:5){
            path.move(to:CGPoint(x:rect.minX+x,y:rect.maxY))
            path.addLine(to:CGPoint(x:rect.minX+x+rect.height,y:rect.minY))
        }
        return path
    }
}
struct StatisticsDashboard:NSViewRepresentable {
    let records:[SessionRecord]
    var now=Date()
    func makeNSView(context:Context)->StatisticsScrollView{
        StatisticsScrollView(content:StatisticsContent(records:records,now:now))
    }
    func updateNSView(_ view:StatisticsScrollView,context:Context){
        view.update(StatisticsContent(records:records,now:now))
    }
}
/// Overlay scrolling keeps the document width independent of scroller visibility.
final class StatisticsScrollView:NSScrollView {
    private struct Document:View {
        let content:StatisticsContent
        let width:CGFloat
        var body:some View{
            content.foregroundStyle(DianyuDesign.primary).buttonStyle(FlatButtonStyle())
                .frame(width:width,alignment:.topLeading).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var content:StatisticsContent
    private let host:ClearHostingView<Document>
    private var documentWidth:CGFloat=0
    private var contentChanged=true
    init(content:StatisticsContent){
        self.content=content
        host=ClearHostingView(rootView:Document(content:content,width:650))
        super.init(frame:.zero)
        host.sizingOptions=[.intrinsicContentSize]
        drawsBackground=false
        borderType = .noBorder
        scrollerStyle = .overlay
        hasVerticalScroller=true
        autohidesScrollers=false
        documentView=host
    }
    required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}
    func update(_ content:StatisticsContent){self.content=content;contentChanged=true;needsLayout=true}
    override func layout(){
        super.layout()
        let width=contentSize.width
        guard width>0 else{return}
        if contentChanged || documentWidth != width{
            documentWidth=width;contentChanged=false
            host.rootView=Document(content:content,width:width)
        }
        let height=max(contentSize.height,ceil(host.intrinsicContentSize.height))
        let size=NSSize(width:width,height:height)
        if host.frame.size != size{host.setFrameSize(size)}
    }
}
/// Shared content keeps preview rendering identical to the live scroll page.
struct StatisticsContent:View {
    let records:[SessionRecord]
    var now=Date()
    var interactive=true
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
                    ActivityCalendarView(activity:activity,interactive:interactive,previous:{periodOffset-=1},next:{periodOffset+=1})
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
    let interactive:Bool
    let previous:()->Void,next:()->Void
    var body:some View{
        let months=activity.months
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:8){
                Text("听写活动").font(.system(size:12,weight:.medium));Spacer()
                Text(activity.rangeLabel).font(.system(size:11)).foregroundStyle(DianyuDesign.secondary)
                navigation("上一段听写活动",symbol:"chevron.left",action:previous).disabled(!activity.canGoBack)
                navigation("下一段听写活动",symbol:"chevron.right",action:next).disabled(!activity.canGoForward)
            }
            ActivityPlotLayout(monthColumns:months.map(\.column)){
                ForEach(["日","一","二","三","四","五","六"],id:\.self){label in
                    Text(label).font(.system(size:10)).foregroundStyle(DianyuDesign.secondary)
                }
                ActivityHeatmap(days:activity.days,interactive:interactive)
                ForEach(months){month in
                    Text(month.title).font(.system(size:10)).foregroundStyle(DianyuDesign.secondary)
                }
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
}
private struct ActivityPlotLayout:Layout {
    let monthColumns:[Int]
    private let axisWidth:CGFloat=22
    private let monthHeight:CGFloat=32
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout())->CGSize{
        let grid=ActivityGridMetrics(width:max(320,(proposal.width ?? 622)-axisWidth))
        return CGSize(width:grid.width+axisWidth,height:grid.height+monthHeight)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout()){
        let grid=ActivityGridMetrics(width:bounds.width-axisWidth)
        for row in 0..<grid.rows{
            subviews[row].place(at:CGPoint(x:bounds.minX+6,y:bounds.minY+grid.frame(row).midY),anchor:.center,proposal:.unspecified)
        }
        let left=bounds.minX+axisWidth
        subviews[grid.rows].place(at:CGPoint(x:left,y:bounds.minY),anchor:.topLeading,
                                 proposal:ProposedViewSize(width:grid.width,height:grid.height))
        for (index,column) in monthColumns.enumerated(){
            let x=min(grid.frame(column*grid.rows).minX,grid.width-32)
            subviews[grid.rows+1+index].place(at:CGPoint(x:left+x,y:bounds.minY+grid.height+14),anchor:.topLeading,proposal:.unspecified)
        }
    }
}
private struct ActivityHeatmap:View {
    let days:[StatisticsActivity.Day]
    let interactive:Bool
    var body:some View{
        Canvas{context,size in
            let grid=ActivityGridMetrics(width:size.width)
            let radius=min(5,grid.cell*0.25)
            for day in days{
                let rect=grid.frame(day.index)
                let path=RoundedRectangle(cornerRadius:radius).path(in:rect)
                switch day.kind{
                case .beforeHistory:
                    var cell=context
                    cell.clip(to:path)
                    cell.stroke(ActivityHatching().path(in:rect),with:.color(ActivityColors.hatch),lineWidth:1.2)
                case .future:
                    let inset=rect.insetBy(dx:0.5,dy:0.5)
                    let outline=RoundedRectangle(cornerRadius:max(0,radius-0.5)).path(in:inset)
                    context.stroke(outline,with:.color(ActivityColors.future),lineWidth:1)
                case .empty,.activity:
                    context.fill(path,with:.color(ActivityColors.levels[day.level]))
                }
            }
        }
        .overlay{if interactive{ActivityHeatmapInteraction(days:days)}}
    }
}
private struct ActivityHeatmapInteraction:NSViewRepresentable {
    let days:[StatisticsActivity.Day]
    func makeNSView(context:Context)->ActivityHeatmapView{ActivityHeatmapView(frame:.zero)}
    func updateNSView(_ view:ActivityHeatmapView,context:Context){view.update(days)}
}
/// Supply native tooltips and accessibility without making each cell a view.
private final class ActivityHeatmapView:NSView,NSViewToolTipOwner {
    private var days:[StatisticsActivity.Day]=[]
    private var toolTips:[NSView.ToolTipTag:Int]=[:]
    private var dayElements:[NSAccessibilityElement]?
    private var toolTipSize=CGSize.zero
    override var isFlipped:Bool{true}

    override init(frame:NSRect){
        super.init(frame:frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("每日听写活动")
    }
    required init?(coder:NSCoder){fatalError("init(coder:) unavailable")}

    func update(_ days:[StatisticsActivity.Day]){
        guard self.days != days else{return}
        self.days=days;dayElements=nil
        updateToolTips()
    }
    override func layout(){
        super.layout()
        if bounds.size != toolTipSize{updateToolTips()}
    }
    private func updateToolTips(){
        removeAllToolTips();toolTips.removeAll();toolTipSize=bounds.size
        guard !bounds.isEmpty else{return}
        let grid=ActivityGridMetrics(width:bounds.width)
        for day in days {
            let frame=grid.frame(day.index)
            toolTips[addToolTip(frame,owner:self,userData:nil)]=day.index
            dayElements?[day.index].setAccessibilityFrameInParentSpace(frame)
        }
    }
    func view(_ view:NSView,stringForToolTip tag:NSView.ToolTipTag,point:NSPoint,userData:UnsafeMutableRawPointer?)->String{
        guard let index=toolTips[tag] else{return ""}
        return description(for:days[index])
    }
    override func accessibilityChildren()->[Any]?{
        if dayElements==nil{
            let grid=ActivityGridMetrics(width:bounds.width)
            dayElements=days.map{day in
                let element=NSAccessibilityElement()
                element.setAccessibilityRole(.staticText)
                element.setAccessibilityLabel(description(for:day))
                element.setAccessibilityParent(self)
                element.setAccessibilityFrameInParentSpace(grid.frame(day.index))
                return element
            }
        }
        return dayElements
    }
    private func description(for day:StatisticsActivity.Day)->String{
        let text=day.date.formatted(.dateTime.year().month().day().weekday())
        switch day.kind{
        case .future:return text+"，未来日期"
        case .beforeHistory:return text+"，早于首条听写记录"
        default:return text+"，\(day.count) 次听写"
        }
    }
}
