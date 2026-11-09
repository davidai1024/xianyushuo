import Foundation

/// Calendar days, not 24-hour offsets: keep weekday rows correct across DST.
struct StatisticsActivity {
    enum DayKind:Equatable {case beforeHistory,empty,activity(Int),future}
    struct Day:Identifiable {
        let index:Int,date:Date,count:Int,kind:DayKind
        var id:Int{index}
        var level:Int{switch count{case ...0:return 0;case 1...2:return 1;case 3...5:return 2;case 6...9:return 3;default:return 4}}
    }
    struct Month:Identifiable {let column:Int,title:String;var id:Int{column}}
    let calendar:Calendar,today:Date,start:Date,end:Date,firstRecorded:Date?
    let counts:[Date:Int],offset:Int
    var activeDays:Int{counts.keys.filter{$0<=today}.count}
    var canGoBack:Bool{firstRecorded.map{$0<start} ?? false}
    var canGoForward:Bool{offset<0}
    var rangeLabel:String{
        let first=calendar.dateComponents([.year,.month],from:start),last=calendar.dateComponents([.year,.month],from:end)
        return first.year==last.year ? "\(first.year!)年 \(first.month!)月—\(last.month!)月" : "\(first.year!)年\(first.month!)月—\(last.year!)年\(last.month!)月"
    }
    init(records:[SessionRecord],now:Date=Date(),offset:Int=0,calendar:Calendar = .current){
        self.calendar=calendar;self.offset=min(0,offset)
        let today=calendar.startOfDay(for:now);self.today=today
        let sunday=calendar.date(byAdding:.day,value:1-calendar.component(.weekday,from:today),to:today)!
        start=calendar.date(byAdding:.day,value:(min(0,offset)*26-25)*7,to:sunday)!
        end=calendar.date(byAdding:.day,value:181,to:start)!
        counts=Dictionary(records.filter(\.counted).map{(calendar.startOfDay(for:$0.created),1)},uniquingKeysWith:+)
        firstRecorded=counts.keys.filter{$0<=today}.min()
    }
    var days:[Day]{(0..<182).map{index in
        let date=calendar.date(byAdding:.day,value:index,to:start)!,count=counts[date] ?? 0
        let kind:DayKind=date>today ? .future : (firstRecorded==nil || date<firstRecorded!) ? .beforeHistory : count==0 ? .empty : .activity(count)
        return Day(index:index,date:date,count:count,kind:kind)
    }}
    var months:[Month]{
        var result:[Month]=[]
        for column in 0..<26{
            let day=calendar.date(byAdding:.day,value:column*7,to:start)!
            let firstOfMonth=(0..<7).compactMap{calendar.date(byAdding:.day,value:$0,to:day)}.first{calendar.component(.day,from:$0)==1}
            if column==0 || firstOfMonth != nil{
                let date=firstOfMonth ?? day
                if let previous=result.last,column-previous.column<2{result.removeLast()}
                result.append(Month(column:column,title:"\(calendar.component(.month,from:date))月"))
            }
        }
        return result
    }
}
