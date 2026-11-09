import Foundation
import AppKit
import SwiftUI
import ApplicationServices
import NaturalLanguage

struct CorrectionProposal:Identifiable,Equatable {
    let id=UUID()
    let removed:String
    let word:String
}
/// Only compare our own insertion. Prefix/suffix changes invalidate the context.
struct CorrectionContext {
    let prefix:String,suffix:String,inserted:String
    init?(baseline:String,inserted:String){
        guard !inserted.isEmpty,baseline.utf16.count<=32000,let range=baseline.range(of:inserted),baseline.range(of:inserted,range:range.upperBound..<baseline.endIndex)==nil else{return nil}
        prefix=String(baseline[..<range.lowerBound]);suffix=String(baseline[range.upperBound...]);self.inserted=inserted
    }
    func edited(in value:String)->String?{
        guard value.utf16.count<=32000,value.hasPrefix(prefix),value.hasSuffix(suffix),value.count>=prefix.count+suffix.count else{return nil}
        return String(value.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
enum CorrectionLearning {
    static let preferenceKey="dianyu.suggestCorrections"
    static var enabled:Bool{UserDefaults.standard.object(forKey:preferenceKey)as?Bool ?? true}
    private static let tokenPattern=try! NSRegularExpression(pattern:"(?:--?[A-Za-z][A-Za-z0-9_-]*|[A-Za-z][A-Za-z0-9_]*(?:[.'’/:@-][A-Za-z0-9_]+)*(?:\\+{1,2}|#)?)|\\X")
    private struct Atom {let text:String;let range:NSRange}
    private static func atoms(_ text:String)->[Atom]{let ns=text as NSString;return tokenPattern.matches(in:text,range:NSRange(location:0,length:ns.length)).map{Atom(text:ns.substring(with:$0.range),range:$0.range)}}
    private static func han(_ text:String)->Bool{!text.isEmpty && text.unicodeScalars.allSatisfy{$0.value>=0x3400 && $0.value<=0x9fff}}
    /// A one-character Chinese correction often changes a whole term: 测是→测试,
    /// 吴光标→无光标, 现代式→现代诗. Keep the lexical context in the suggestion.
    private static func chineseCandidate(_ text:String,range:NSRange,in full:String)->String{
        guard text.count==1 else{return text}
        let tokenizer=NLTokenizer(unit:.word);tokenizer.string=full;tokenizer.setLanguage(.simplifiedChinese)
        var tokens:[(String,NSRange)]=[]
        tokenizer.enumerateTokens(in:full.startIndex..<full.endIndex){r,_ in tokens.append((String(full[r]),NSRange(r,in:full)));return true}
        guard let index=tokens.firstIndex(where:{NSIntersectionRange($0.1,range).length>0})else{return text}
        let term=tokens[index]
        if han(term.0),term.0.count>=2,term.0.count<=8{return term.0}
        let stop:Set<String>=["这","那","这个","那个","一个","这是","请","把","将","是","在","有","的","了","和","很","更","都","不","也","就","个","首","本","再","我","你","他","她","它","呢","吗","啊","哦","嗯","好","要","想","希望","觉得","已经","需要","使用","打开","检查","测试"]
        guard !stop.contains(term.0)else{return text}
        // Prefer an adjacent two/three-character lexical stem. Fall back to a
        // single-character stem only when it is not a function word.
        let neighbors=[index-1,index+1].filter{tokens.indices.contains($0)}.sorted{tokens[$0].0.count>tokens[$1].0.count}
        for neighbor in neighbors{
            let next=tokens[neighbor]
            guard han(next.0),!stop.contains(next.0),next.0.count<=3 else{continue}
            if neighbor<index,NSMaxRange(next.1)==term.1.location{return next.0+term.0}
            if neighbor>index,NSMaxRange(term.1)==next.1.location{return term.0+next.0}
        }
        return text
    }
    private static func useful(_ word:String)->Bool{
        guard (try? VocabularyRules.validated(word)) != nil,word.unicodeScalars.contains(where:CharacterSet.alphanumerics.contains)else{return false}
        if ["a","an","the","is","are","was","嗯","好的","然后","这个","那个","是否","不是","可以","已经","一下"].contains(word.lowercased()){return false}
        if word.unicodeScalars.allSatisfy({$0.value>=0x3400 && $0.value<=0x9fff}){return word.count<=8}
        return word.first?.isASCII==true && word.first?.isLetter==true || word.hasPrefix("-")
    }
    static func proposals(before:String,after:String,existing:[String])->[CorrectionProposal]{
        guard before != after,before.utf16.count<=32000,after.utf16.count<=32000 else{return []}
        let a=atoms(before),b=atoms(after),left=a.map(\.text),right=b.map(\.text)
        guard left.count<=32000,right.count<=32000 else{return []}
        // A wholesale rewrite is prose, not a vocabulary correction. Also bounds
        // the worst case of the sequence difference for long recordings.
        if max(left.count,right.count)>256 {
            let common=Set(left).intersection(Set(right)).count
            guard Double(common)/Double(max(1,min(Set(left).count,Set(right).count)))>=0.5 else{return []}
        }
        let difference=right.difference(from:left)
        var deleted=Set<Int>(),inserted=Set<Int>()
        for change in difference{switch change{case .remove(let offset,_,_):deleted.insert(offset);case .insert(let offset,_,_):inserted.insert(offset)}}
        var i=0,j=0,seen=Set(existing.map(VocabularyRules.key)),values:[CorrectionProposal]=[]
        while i<a.count || j<b.count{
            if deleted.contains(i) || inserted.contains(j){
                let oldStart=i,newStart=j
                while (i<a.count && deleted.contains(i)) || (j<b.count && inserted.contains(j)){
                    if i<a.count && deleted.contains(i){i+=1}
                    if j<b.count && inserted.contains(j){j+=1}
                }
                guard i>oldStart,j>newStart else{continue}
                let old=left[oldStart..<i].joined(),new=right[newStart..<j].joined()
                guard old.unicodeScalars.contains(where:CharacterSet.alphanumerics.contains),new.unicodeScalars.contains(where:CharacterSet.alphanumerics.contains),old.unicodeScalars.count<=80,new.unicodeScalars.count<=160,VocabularyRules.key(old) != VocabularyRules.key(new)else{continue}
                // A shrinking prefix/suffix means the user is still deleting.
                if new.count<old.count,(old.hasPrefix(new)||old.hasSuffix(new)){continue}
                var candidates:[String]=[],han="",hanRange=NSRange(location:0,length:0)
                func flush(){if !han.isEmpty{candidates.append(chineseCandidate(han,range:hanRange,in:after));han="";hanRange.length=0}}
                for k in newStart..<j {
                    let atom=b[k]
                    if atom.text.unicodeScalars.allSatisfy({$0.value>=0x3400 && $0.value<=0x9fff}){if han.isEmpty{hanRange=atom.range}else{hanRange.length=NSMaxRange(atom.range)-hanRange.location};han+=atom.text}
                    else{
                        flush()
                        // Do not offer the stem of an unfinished filename/path.
                        let next=k+1<b.count ? b[k+1].text:""
                        if useful(atom.text),![".","/","_","-","@"].contains(next){candidates.append(atom.text)}
                    }
                }
                flush()
                for candidate in candidates where useful(candidate){
                    let key=VocabularyRules.key(candidate)
                    guard !seen.contains(key),!left.contains(where:{VocabularyRules.key($0)==key})else{continue}
                    seen.insert(key);values.append(CorrectionProposal(removed:old,word:candidate))
                }
            }else{
                if i<a.count{i+=1};if j<b.count{j+=1}
            }
        }
        return values
    }
}
/// The production polling loop and the trace tests use this same state machine.
/// Input gestures do not matter: it follows snapshots through empty/intermediate
/// values, keeps the original insertion, and invalidates stale visible proposals.
struct CorrectionTrackingSession {
    enum Event {case waiting,changed,proposal(CorrectionProposal),alreadyKnown,noCandidate,outsideInsertion}
    let context:CorrectionContext
    private var lastValue:String
    private var changedAt:TimeInterval
    private var checkedValue:String?
    private var checkedWords:Set<String>=[]
    private var ignored=Set<String>()
    private(set) var current:CorrectionProposal?
    let settleDelay:TimeInterval=0.7
    init(context:CorrectionContext,baseline:String,now:TimeInterval){self.context=context;lastValue=baseline;changedAt=now;checkedValue=baseline}
    mutating func observe(_ value:String,at now:TimeInterval,existing:[String],composing:Bool=false,force:Bool=false)->Event{
        guard let edited=context.edited(in:value)else{return .outsideInsertion}
        if value != lastValue || composing{
            lastValue=value;changedAt=now;checkedValue=nil;current=nil
            if !force || composing{return .changed}
        }
        guard force || now-changedAt>=settleDelay else{return .waiting}
        let words=Set(existing.map(VocabularyRules.key)).union(ignored)
        guard checkedValue != value || checkedWords != words else{return .waiting}
        checkedValue=value;checkedWords=words
        let candidates=CorrectionLearning.proposals(before:context.inserted,after:edited,existing:[])
        if let proposal=candidates.first(where:{!words.contains(VocabularyRules.key($0.word))}){
            current=proposal;return .proposal(proposal)
        }
        current=nil
        if !candidates.isEmpty,candidates.allSatisfy({Set(existing.map(VocabularyRules.key)).contains(VocabularyRules.key($0.word))}){return .alreadyKnown}
        return .noCandidate
    }
    mutating func ignore(_ word:String){ignored.insert(VocabularyRules.key(word));current=nil;checkedValue=nil}
    mutating func accepted(){current=nil;checkedValue=nil}
}
@MainActor final class CorrectionMonitor {
    private var timer:Timer?
    private var target:PasteTarget?
    private var session:CorrectionTrackingSession?
    private var started=Date.distantPast
    private var existing:()->[String]={[]}
    private var unreadable=0,lastStatus=""
    var onProposal:((CorrectionProposal)->Void)?
    var onInvalidated:(()->Void)?
    var onStatus:((String)->Void)?
    private func status(_ value:String){guard lastStatus != value else{return};lastStatus=value;onStatus?(value)}
    func start(target:PasteTarget,inserted:String,observedBaseline:String?,existing:@escaping()->[String]){
        stop();lastStatus=""
        guard CorrectionLearning.enabled else{status("disabled");return}
        guard let baseline=observedBaseline,let context=CorrectionContext(baseline:baseline,inserted:inserted)else{status("no_unique_observed_insertion");return}
        self.target=target;self.existing=existing;started=Date();unreadable=0
        session=CorrectionTrackingSession(context:context,baseline:baseline,now:started.timeIntervalSinceReferenceDate)
        status("monitoring")
        timer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true){[weak self]_ in Task{@MainActor in self?.poll()}}
    }
    func stop(_ reason:String="stopped"){
        let active=timer != nil;timer?.invalidate();timer=nil;target=nil;session=nil;existing={[]}
        if active{status(reason)}
    }
    private func composing(_ input:AXUIElement)->Bool{
        guard let value=InputAccess.value(input,"AXMarkedTextRange"),CFGetTypeID(value)==AXValueGetTypeID()else{return false}
        var range=CFRange();return AXValueGetValue(unsafeBitCast(value,to:AXValue.self),.cfRange,&range) && range.location>=0 && range.length>0
    }
    private func observe(_ value:String,composing:Bool=false,force:Bool=false){
        guard var session else{return}
        let event=session.observe(value,at:Date().timeIntervalSinceReferenceDate,existing:existing(),composing:composing,force:force)
        self.session=session
        switch event{
        case .changed:status("editing");onInvalidated?()
        case .proposal(let proposal):status("suggested");onProposal?(proposal)
        case .outsideInsertion:stop("outside_insertion_changed")
        case .noCandidate:status("no_new_vocabulary")
        case .alreadyKnown:status("already_in_vocabulary")
        case .waiting:break
        }
    }
    private func poll(){
        guard CorrectionLearning.enabled else{stop("disabled");return}
        guard Date().timeIntervalSince(started)<180 else{stop("timeout");return}
        guard let target,NSWorkspace.shared.frontmostApplication?.processIdentifier==target.pid else{stop("foreground_changed");return}
        guard let input=target.correctionInput(),let value=InputAccess.string(input,kAXValueAttribute)else{unreadable+=1;if unreadable>=10{stop("input_unreadable_or_changed")};return}
        unreadable=0;observe(value,composing:composing(input))
    }
    func canAccept(_ word:String)->Bool{
        // When the input is still active, never save a suggestion superseded by
        // more typing between the last poll and the click. A retained suggestion
        // can also be explicitly reviewed later in the app's vocabulary page.
        guard let target,let session,NSWorkspace.shared.frontmostApplication?.processIdentifier==target.pid else{return true}
        guard let input=target.correctionInput(),!composing(input),let value=InputAccess.string(input,kAXValueAttribute),let edited=session.context.edited(in:value)else{return false}
        return CorrectionLearning.proposals(before:session.context.inserted,after:edited,existing:[]).contains{VocabularyRules.key($0.word)==VocabularyRules.key(word)}
    }
    func ignore(_ word:String){session?.ignore(word);status("ignored")}
    func accepted(){session?.accepted();status("confirmed")}
    func commit(){
        if let target,let input=target.correctionInput(),let value=InputAccess.string(input,kAXValueAttribute){
            // Some chat editors clear before the global Return monitor runs.
            // Preserve an already-settled proposal; never invent one from an
            // unseen submitted value or a half-typed historical snapshot.
            if !value.isEmpty || session?.current == nil{observe(value,composing:composing(input),force:true)}
        }
        stop("submitted")
    }
    deinit{timer?.invalidate()}
}
/// Non-activating: the suggestion must never steal the user's typing focus.
final class CorrectionPanel:NSPanel {override var canBecomeKey:Bool{false};override var canBecomeMain:Bool{false}}
@MainActor final class CorrectionPrompt {
    private var panel:CorrectionPanel?
    func show(_ proposal:CorrectionProposal,error:String="",accept:@escaping()->Void,dismiss:@escaping()->Void){
        close()
        let panel=CorrectionPanel(contentRect:NSRect(x:0,y:0,width:390,height:146),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false;panel.level = .floating;panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.hidesOnDeactivate=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentView=NSHostingView(rootView:CorrectionPromptView(proposal:proposal,error:error,accept:accept,dismiss:dismiss))
        let area=(NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        panel.setFrameOrigin(NSPoint(x:area.maxX-414,y:area.minY+84));panel.orderFrontRegardless();self.panel=panel
    }
    func close(){panel?.orderOut(nil);panel=nil}
}
struct CorrectionPromptView:View {
    let proposal:CorrectionProposal
    var error=""
    let accept:()->Void,dismiss:()->Void
    var body:some View{
        VStack(alignment:.leading,spacing:10){
            HStack{Text("记住这次改字？").font(.system(size:14,weight:.semibold));Spacer();Button(action:dismiss){Image(systemName:"xmark")}.buttonStyle(FlatButtonStyle(kind:.quiet)).accessibilityLabel("忽略词表建议")}
            Text(error.isEmpty ? "将“\(proposal.word)”加入个人词表，下次识别时提供提示。":error).font(.system(size:12)).foregroundStyle(DianyuDesign.secondary).lineLimit(2).fixedSize(horizontal:false,vertical:true)
            HStack{Text("仅在本机保存").font(.system(size:11)).foregroundStyle(DianyuDesign.secondary);Spacer();Button("忽略",action:dismiss);Button("加入词表",action:accept).buttonStyle(FlatButtonStyle(kind:.primary))}
        }.padding(18).frame(width:390,height:146).foregroundStyle(DianyuDesign.primary).background(DianyuDesign.group,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(DianyuDesign.line)).buttonStyle(FlatButtonStyle())
    }
}
