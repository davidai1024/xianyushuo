import Foundation
import AppKit

@main struct VocabularyBoundaryTests {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuWords-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);defer{try?FileManager.default.removeItem(at:root)}
        var count=0
        func check(_ ok:Bool,_ label:String){precondition(ok,label);count+=1}
        func rejects(_ body:()throws->Void)->Bool{do{try body();return false}catch{return true}}
        check(try VocabularyRules.validated(String(repeating:"a",count:80)).unicodeScalars.count==80,"80 code points accepted")
        check(rejects{_=try VocabularyRules.validated(String(repeating:"a",count:81))},"81 code points rejected")
        check(rejects{_=try VocabularyRules.validated(String(repeating:"e\u{301}",count:41))},"Combining characters use code points, not grapheme count")
        check(rejects{_=try VocabularyRules.validated("word\u{2028}word")},"Unicode line separator rejected")
        check(rejects{_=try VocabularyRules.validated("  \n ")},"Empty entry rejected")
        check(VocabularyRules.key(" ＴＨＩＥＦ ")==VocabularyRules.key("thief"),"NFKC and case folding")
        check(VocabularyRules.key("Straße")==VocabularyRules.key("STRASSE"),"Unicode case-fold expansion")
        let store=LibraryStore();try store.saveVocabulary([VocabularyEntry(word:"thief"),VocabularyEntry(word:"无光标")])
        let snapshot=store.vocabulary
        let batch=try VocabularyRules.imported(Data("[\" ＴＨＩＥＦ \",\"Cache\"]".utf8),json:true,existing:snapshot)
        check(batch.added==1 && batch.skipped==1,"Import reports normalized duplicates separately")
        check(batch.values.last?.word=="Cache","Stored spelling is preserved")
        check(rejects{_=try VocabularyRules.imported(Data("[\"valid\",\"\"]".utf8),json:true,existing:snapshot)},"Invalid later entry rejects entire batch")
        check(store.vocabulary==snapshot && LibraryStore().vocabulary==snapshot,"Rejected batch leaves memory and disk unchanged")
        check(rejects{_=try VocabularyRules.imported(Data("{broken".utf8),json:true,existing:snapshot)},"Invalid JSON cannot become a literal word")
        check(rejects{_=try VocabularyRules.imported(Data(repeating:97,count:1_048_577),json:false,existing:snapshot)},"Oversized import rejected before parsing")
        let full=(0..<128).map{VocabularyEntry(word:"word\($0)")}
        check(rejects{_=try VocabularyRules.imported(Data("another".utf8),json:false,existing:full)},"Capacity rejects whole import")
        var edited=VocabularyEntry(word:"  ProductName  ");edited.enabled=false
        try store.saveVocabulary([edited]);check(store.vocabulary[0].word=="ProductName" && store.vocabulary[0].id==edited.id && !store.vocabulary[0].enabled,"Trim preserves identity, case and enabled state")
        check(rejects{try store.saveVocabulary([VocabularyEntry(word:"Ａ"),VocabularyEntry(word:"a")])},"Manual edits also enforce normalized uniqueness")
        print("Vocabulary boundary checks passed:",count)
    }
}
