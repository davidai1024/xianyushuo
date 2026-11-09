import AppKit
import Foundation

@main struct CorrectionLearningTests {
    @MainActor static func main()throws {
        _=NSApplication.shared
        var checks=0
        func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
        func words(_ a:String,_ b:String,_ existing:[String]=[])->[String]{CorrectionLearning.proposals(before:a,after:b,existing:existing).map(\.word)}
        check(words("这个desgin.md还有问题。","这个design.md还有问题。")==["design.md"],"Expand the entire corrected filename")
        check(words("请检查 design.md。","请检查 design.test。")==["design.test"],"Real Codex chat correction expands changed suffix")
        check(words("这个第三代MD是否有问题？","这个design.md是否有问题？")==["design.md"],"Chinese misrecognition to filename")
        check(words("这个set不是thief。","这个theft不是thief。")==["theft"],"Full corrected English token")
        check(words("这是吴广彪测试。","这是无光标测试。")==["无光标"],"Suggest the corrected phrase instead of surrounding prose")
        check(words("这是吴光标测试。","这是无光标测试。")==["无光标"],"Single-character Chinese repair keeps its complete term")
        check(words("这首现代式很不错。","这首现代诗很不错。")==["现代诗"],"Chinese term ending repair retains the lexical stem")
        check(words("请检查词标。","请检查词表。")==["词表"],"One-character dictionary repair offers the complete term")
        check(words("请打开咸鱼硕。","请打开咸鱼说。")==["咸鱼说"],"Brand ending repair keeps the complete name")
        check(words("这是测是。","这是测试。")==["测试"],"Tokenizer expands a correction inside a Chinese word")
        check(words("design","design.md")==["design.md"],"Completing an identifier is different from appending new prose")
        check(words("这是嗯测试","这是测试").isEmpty,"Deletion does not create vocabulary")
        check(words("这是测试","这是新的测试").isEmpty,"Insertion does not create vocabulary")
        check(words("hello world","hello, world").isEmpty,"Punctuation does not create vocabulary")
        check(words("hello world","hello  world").isEmpty,"Whitespace does not create vocabulary")
        check(words("Design.MD","design.md").isEmpty,"Case-only change is ignored")
        check(words("desgin.md","design.md",["ＤＥＳＩＧＮ．ＭＤ"]).isEmpty,"NFKC dedup applies to suggestions")
        check(words("desgin.md","design.md",["design.md"]).isEmpty,"Existing words not re-suggested")
        check(words("哦，这是原文。","嗯，这是原文。").isEmpty,"Filler change is not a word")
        check(words("the cat","a cat").isEmpty,"Common articles ignored")
        check(words(String(repeating:"错",count:81),String(repeating:"对",count:81)).isEmpty,"Large replacement ignored")
        let context=CorrectionContext(baseline:"现有前缀😀这个desgin.md还有问题。已有后缀",inserted:"这个desgin.md还有问题。")!
        check(context.edited(in:"现有前缀😀这个design.md还有问题。已有后缀")=="这个design.md还有问题。","Only inserted span is monitored")
        check(context.edited(in:"改了前缀😀这个design.md还有问题。已有后缀")==nil,"Edits outside the inserted prefix stop learning")
        check(context.edited(in:"现有前缀😀这个design.md还有问题。改了后缀")==nil,"Suffix edits stop learning")
        check(CorrectionContext(baseline:"重复重复",inserted:"重复")==nil,"Ambiguous repeated insertion skipped")
        check(CorrectionContext(baseline:"没有插入",inserted:"新内容")==nil,"Missing insertion skipped")
        check(CorrectionContext(baseline:String(repeating:"a",count:32001),inserted:"a")==nil,"Large target field skipped")
        let target=PasteTarget(pid:nil,bundleID:"im.muse.dianyu.test",element:nil,window:nil,role:"",focusedRole:"",focusedOwner:nil,identifier:"",geometry:nil,text:nil,selection:nil,clipboardVersion:0)
        let receipt=DeliveryReceipt(state:"unverified",message:"test",audit:[:],observedInsertionBaseline:"请检查 design.md。")
        let monitor=CorrectionMonitor();var status="";monitor.onStatus={status=$0}
        monitor.start(target:target,inserted:"请检查 design.md。",observedBaseline:receipt.observedInsertionBaseline,existing:{[]})
        check(status=="monitoring","One proven insertion can arm correction detection despite an unsettled delivery receipt")
        monitor.stop()
        monitor.start(target:target,inserted:"请检查 design.md。",observedBaseline:nil,existing:{[]})
        check(status=="no_unique_observed_insertion","A sent paste without observed content cannot arm learning")
        let internalMic=MicrophoneChoice(id:"built",name:"Mac",device:1,builtIn:true),pods=MicrophoneChoice(id:"pods",name:"AirPods",device:2,builtIn:false)
        let choices=[internalMic,pods]
        check(AudioDevices.resolve(uid:"",preferBuiltIn:false,choices:choices,defaultDevice:2)?.id=="pods","Default resolves to AirPods")
        check(AudioDevices.resolve(uid:"",preferBuiltIn:false,choices:choices,defaultDevice:1)?.id=="built","Changed default resolves anew")
        check(AudioDevices.resolve(uid:"pods",preferBuiltIn:true,choices:choices,defaultDevice:1)?.id=="pods","Explicit device overrides built-in preference")
        check(AudioDevices.resolve(uid:"missing",preferBuiltIn:true,choices:choices,defaultDevice:1)==nil,"Disconnected explicit device never silently falls back")
        check(AudioDevices.resolve(uid:"",preferBuiltIn:true,choices:choices,defaultDevice:2)?.id=="built","Opt-in built-in preference works")
        check(AudioDevices.resolve(uid:"",preferBuiltIn:false,choices:choices,defaultDevice:nil)==nil,"Missing default fails closed")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuCorrectionTests-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);defer{try? FileManager.default.removeItem(at:root)}
        let store=LibraryStore();try store.saveVocabulary([VocabularyEntry(word:"theft")]);let old=store.vocabulary
        _=words("desgin.md","design.md");check(store.vocabulary.map(\.id)==old.map(\.id) && store.activeWords==["theft"],"Detection itself never writes vocabulary")
        var accepted=store.vocabulary;accepted.append(VocabularyEntry(word:"design.md"));try store.saveVocabulary(accepted)
        check(LibraryStore().activeWords.contains("design.md"),"Confirmed corrected word survives reload")
        check(store.sessions.isEmpty,"Correction fixtures do not create statistics/history")
        print("Correction and microphone routing checks passed:",checks)
    }
}
