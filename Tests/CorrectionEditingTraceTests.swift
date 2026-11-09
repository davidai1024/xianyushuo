import Foundation
import AppKit

@main struct CorrectionEditingTraceTests {
    static func main(){
        var checks=0,paths=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        let baseline="请检查 design.md。",final="请检查 design.test。"
        func tracker(_ original:String=baseline)->CorrectionTrackingSession{CorrectionTrackingSession(context:CorrectionContext(baseline:original,inserted:original)!,baseline:original,now:0)}
        func trace(_ label:String,_ frames:[String],expected:String="design.test",original:String=baseline){
            var session=tracker(original),now=0.0
            for frame in frames{now+=0.1;_ = session.observe(frame,at:now,existing:[])}
            let last=frames.last!;_ = session.observe(last,at:now+2,existing:[])
            check(session.current?.word==expected,label);paths+=1
        }
        trace("Suffix selected and replaced atomically",[final])
        trace("Suffix selected, deleted, and pasted",["请检查 design。",final])
        trace("Suffix selected without dot",["请检查 design.。",final])
        trace("Suffix backspaced one letter at a time",["请检查 design.m。","请检查 design.。","请检查 design.t。","请检查 design.te。","请检查 design.tes。",final])
        trace("Forward Delete from the start of extension",["请检查 design.d。","请检查 design.。",final])
        trace("Entire filename selected then retyped",["请检查 。","请检查 d。","请检查 de。","请检查 des。","请检查 design。",final])
        trace("Cmd+Backspace word removal then replacement",["请检查 。",final])
        trace("Cut filename then paste replacement",["请检查 。",final])
        trace("Select all input then type replacement",["","请","请检查 ",final])
        trace("Select all input then paste replacement",["",final])
        trace("Undo and redo before settling",[final,baseline,final])
        trace("Rapid repeated suffix revision",["请检查 design.txt。","请检查 design.tex。",final])
        trace("Delete dot and extension together",["请检查 design。",final])
        trace("Single-letter repair retains whole identifier",["请检查 design.md。"],expected:"design.md",original:"请检查 design.mg。")
        trace("Single English word letter repair",["theft"],expected:"theft",original:"theif")
        trace("Technical C++ suffix correction",["C++"],expected:"C++",original:"C#")
        trace("Underscore identifier partial correction",["请用 user_name"],expected:"user_name",original:"请用 user_nam")
        trace("Slash identifier partial correction",["请用 CI/CD"],expected:"CI/CD",original:"请用 CI/CB")
        trace("Hyphen option partial correction",["请用 --verbose"],expected:"--verbose",original:"请用 --verboze")
        trace("Emoji and combining marks preserve offsets",["🙂 e\u{301} 请检查 design.test。"],expected:"design.test",original:"🙂 e\u{301} 请检查 design.md。")
        var session=tracker();_ = session.observe("请检查 design.。",at:0.1,existing:[]);_ = session.observe("请检查 design.。",at:3,existing:[])
        check(session.current==nil,"Incomplete extension never offers a stem")
        _ = session.observe(final,at:3.1,existing:[]);_ = session.observe(final,at:5,existing:[]);check(session.current?.word=="design.test","Long pause during deletion does not end detection")
        session=tracker();_ = session.observe("",at:0.1,existing:[]);_ = session.observe("",at:4,existing:[]);check(session.current==nil,"Empty intermediate editor never creates a word")
        _ = session.observe(final,at:5,existing:[]);_ = session.observe(final,at:7,existing:[]);check(session.current?.word=="design.test","Retype after a long empty interval still works")
        session=tracker();_ = session.observe("请检查 design.t。",at:0.1,existing:[]);_ = session.observe("请检查 design.t。",at:2,existing:[])
        check(session.current?.word=="design.t","Stable valid one-character extension remains possible")
        _ = session.observe(final,at:2.1,existing:[]);check(session.current==nil,"Further typing invalidates the old visible suggestion immediately")
        _ = session.observe(final,at:4,existing:[]);check(session.current?.word=="design.test","New stable suffix replaces the old suggestion")
        session.ignore("design.test");_ = session.observe(final,at:6,existing:[]);check(session.current==nil,"Ignored candidate is not repeated")
        _ = session.observe("请检查 design.demo。",at:7,existing:[]);_ = session.observe("请检查 design.demo。",at:9,existing:[]);check(session.current?.word=="design.demo","Ignoring one word does not lose a later distinct correction")
        session=tracker();_ = session.observe(final,at:0.1,existing:["design.test"]);let duplicate=session.observe(final,at:2,existing:["design.test"]);check(session.current==nil,"Already learned filename does not produce duplicate prompts")
        if case .alreadyKnown=duplicate{check(true,"Existing-word reason is distinguishable from missed detection")}else{check(false,"Existing word reason")}
        session=tracker();_ = session.observe(final,at:0.1,existing:[]);_ = session.observe(final,at:2,existing:[]);session.accepted();_ = session.observe(final,at:3,existing:["design.test"]);check(session.current==nil,"Accepted word is removed from pending candidates")
        session=tracker();_ = session.observe(final,at:0.1,existing:[]);_ = session.observe(final,at:2,existing:[]);_ = session.observe(baseline,at:2.1,existing:[]);_ = session.observe(baseline,at:4,existing:[]);check(session.current==nil,"Undo clears a stale suggestion")
        session=tracker();_ = session.observe(final,at:0.1,existing:[],composing:true);_ = session.observe(final,at:2,existing:[],composing:true);check(session.current==nil,"Marked IME text is never offered")
        _ = session.observe(final,at:2.1,existing:[]);_ = session.observe(final,at:4,existing:[]);check(session.current?.word=="design.test","Committed IME text can settle normally")
        session=tracker();_ = session.observe(final,at:0.1,existing:[],force:true);check(session.current?.word=="design.test","Submission reads a final edit without requiring a pause")
        session=tracker();_ = session.observe(final,at:0.1,existing:[])
        _ = session.observe(final,at:0.6,existing:[]);check(session.current==nil,"Fast learning still waits for a real typing pause")
        _ = session.observe(final,at:0.85,existing:[]);check(session.current?.word=="design.test","A committed edit is detected within one second")
        session=tracker();_ = session.observe(final,at:0.1,existing:[],composing:true)
        _ = session.observe(final,at:1,existing:[],composing:true);check(session.current==nil,"Long IME composition never proposes prematurely")
        _ = session.observe(final,at:1.2,existing:[]);_ = session.observe(final,at:1.75,existing:[])
        check(session.current?.word=="design.test","IME completion settles after marked text clears")
        for (from,to) in [("这是吴光标测试。","这是无光标测试。"),("这是现代式。","这是现代诗。")]{
            let candidates=CorrectionLearning.proposals(before:from,after:to,existing:[])
            check(!candidates.isEmpty,"Chinese one-character repairs remain detectable")
        }
        let g=[100.0,300,600,40]
        check(CorrectionTargetPolicy.matches(identifier:"composer",role:"AXTextArea",geometry:g,nextIdentifier:"composer",nextRole:"AXTextArea",nextGeometry:[100,250,600,90]),"Read-only learning follows bottom-anchored editor growth")
        check(CorrectionTargetPolicy.matches(identifier:"composer",role:"AXTextArea",geometry:g,nextIdentifier:"composer",nextRole:"AXTextArea",nextGeometry:[100,300,600,90]),"Read-only learning follows top-anchored editor growth")
        for (id,role,geometry) in [("other","AXTextArea",g),("composer","AXTextField",g),("composer","AXTextArea",[100.0,400,600,40]),("composer","AXTextArea",[200.0,300,600,40]),("composer","AXTextArea",[100.0,300,700,40])]{
            check(!CorrectionTargetPolicy.matches(identifier:"composer",role:"AXTextArea",geometry:g,nextIdentifier:id,nextRole:role,nextGeometry:geometry),"Changed editor identity or unrelated geometry cannot be followed")
        }
        check(!CorrectionTargetPolicy.matches(identifier:"",role:"AXTextArea",geometry:g,nextIdentifier:"",nextRole:"AXTextArea",nextGeometry:g),"Anonymous recreated editor is never guessed")
        let gap=String(repeating:"这是保留的中间句子。",count:100)
        let original="请检查 design.md。"+gap+"再打开 broswer。",updated="请检查 design.test。"+gap+"再打开 browser。"
        let proposals=CorrectionLearning.proposals(before:original,after:updated,existing:[])
        check(Set(proposals.map(\.word))==["design.test","browser"],"Separated corrections across long prose are independent")
        session=tracker(original);_ = session.observe(updated,at:0.1,existing:[]);_ = session.observe(updated,at:2,existing:[])
        let first=session.current!.word;session.ignore(first);_ = session.observe(updated,at:3,existing:[]);check(session.current != nil && session.current?.word != first,"Next corrected word is offered after the first decision")
        let large=String(repeating:"保留的长句。",count:2200)
        let begin=Date();let long=CorrectionLearning.proposals(before:large+"design.md",after:large+"design.test",existing:[])
        check(long.map(\.word)==["design.test"],"Very long input retains a local suffix correction")
        check(Date().timeIntervalSince(begin)<2,"Long local correction has a bounded practical processing cost")
        for (a,b) in [("hello world","hello, world"),("这是测试","这是新的测试"),("你好嗯测试","你好测试"),("Design.MD","design.md"),("hello","hello world")]{check(CorrectionLearning.proposals(before:a,after:b,existing:[]).isEmpty,"No new-word prompt for punctuation/prose append/delete/case")}
        let bounded=CorrectionContext(baseline:"原有前缀"+baseline+"原有后缀",inserted:baseline)!
        var scoped=CorrectionTrackingSession(context:bounded,baseline:"原有前缀"+baseline+"原有后缀",now:0)
        if case .outsideInsertion=scoped.observe("改变前缀"+final+"原有后缀",at:1,existing:[]){check(true,"Unrelated content changes stop learning")}else{check(false,"Scope boundary")}
        print("Editing trace checks passed:",checks,"gesture-equivalent paths:",paths)
    }
}
