import Foundation

@main struct StatisticsActivityTests {
    static func main(){
        var checks=0
        func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
        for zone in ["Asia/Shanghai","America/Los_Angeles","Europe/Berlin"]{
            var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:zone)!
            func date(_ year:Int,_ month:Int,_ day:Int)->Date{cal.date(from:DateComponents(year:year,month:month,day:day,hour:12))!}
            func record(_ day:Date,status:String="completed",source:String="microphone")->SessionRecord{
                var r=SessionRecord();r.created=day;r.finished=day;r.status=status;r.source=source;r.raw="测试";r.output="测试";r.duration=2;return r
            }
            for now in [date(2026,11,6),date(2026,3,9),date(2026,11,2),date(2027,1,1)]{
                let yesterday=cal.date(byAdding:.day,value:-1,to:now)!,future=cal.date(byAdding:.day,value:1,to:now)!
                let records=[record(yesterday),record(now),record(now),record(now,status:"cancelled"),record(now,source:"text-test"),record(now,source:"audio-import"),record(now,source:"onboarding"),record(future)]
                let activity=StatisticsActivity(records:records,now:now,calendar:cal),days=activity.days
                check(days.count==182,"26 complete calendar weeks")
                check(cal.component(.weekday,from:activity.start)==1,"Grid always starts on Sunday")
                check(cal.component(.weekday,from:activity.end)==7,"Grid always ends on Saturday")
                check(activity.activeDays==2,"Practice/import/cancel and future do not add active days")
                check(days.first{$0.date==cal.startOfDay(for:now)}?.count==2,"Only completed microphone jobs count")
                check(days.first{$0.date==cal.startOfDay(for:now)}?.level==1,"Low-volume activity uses first blue level")
                check(days.first?.kind == .beforeHistory,"Days before first record are hatched")
                check(!activity.canGoForward && !activity.canGoBack,"Recent-only history disables empty-page navigation")
                for day in days{
                    check(cal.component(.weekday,from:day.date)==day.index%7+1,"Day labels remain correct across DST")
                    check(cal.component(.hour,from:day.date)==0,"Grid uses local day boundaries")
                    if day.date>activity.today{check(day.kind == .future,"Future is outlined even if a clock-skewed record exists")}
                }
                let older=StatisticsActivity(records:records+[record(cal.date(byAdding:.day,value:-400,to:now)!)],now:now,offset:-1,calendar:cal)
                check(older.canGoBack && older.canGoForward,"Older history supports both page directions")
                check(cal.date(byAdding:.day,value:1,to:older.end)==activity.start,"Adjacent pages contain no duplicate or missing dates")
                check(Set(activity.months.map(\.column)).count==activity.months.count,"Month columns are unique")
                check(activity.months.allSatisfy{(0..<26).contains($0.column)},"Month labels stay inside the grid")
            }
            let empty=StatisticsActivity(records:[],now:date(2026,11,6),calendar:cal)
            check(empty.activeDays==0 && empty.firstRecorded==nil,"Empty history has no fabricated activity")
            check(!empty.canGoBack && !empty.canGoForward,"Empty navigation is disabled")
        }
        print("Activity calendar/counting/DST checks passed:",checks)
    }
}
