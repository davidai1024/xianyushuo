import Foundation
import AppKit

@main struct DomainTests {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuTests-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1)
        defer{try? FileManager.default.removeItem(at:root)}
        var checks=0
        func check(_ truth:@autoclosure()->Bool,_ name:String){precondition(truth(),name);checks+=1}
        let defaults=try JSONDecoder().decode(Preferences.self,from:Data("{}".utf8))
        check(!defaults.hideDockIcon && defaults.preserveHeadphoneControls,"Older preferences retain Dock and enable safe headphone idle policy")
        var background=defaults;background.hideDockIcon=true;background.keepMicWarm=true
        let backgroundRestored=try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(background))
        check(backgroundRestored == background,"Background and headphone settings survive restart")
        check(Metrics.count("这个 thief，不是 theft。C") == 7,"Mixed word counter")
        check(Preferences().dictation.matches(KeyBinding(key:61,modifiers:0,standalone:"rightOption",label:"right")),"Default right Option")
        check(Preferences().translation.modifiers==6656,"Translation shift modifier bit")
        var streamDefaults=try JSONDecoder().decode(Preferences.self,from:Data(#"{"cleanup":"structured","keepMicWarm":true,"autoPaste":false}"#.utf8))
        check(streamDefaults.streamWhileRecording && streamDefaults.keepMicWarm && !streamDefaults.autoPaste && streamDefaults.cleanup == .structured,"Streaming default preserves legacy preferences")
        streamDefaults.streamWhileRecording=false
        let streamRestored=try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(streamDefaults))
        check(streamRestored == streamDefaults,"Streaming opt-out survives restart")
        let store=LibraryStore();check(store.storageError.isEmpty,"First launch storage")
        try store.saveVocabulary([VocabularyEntry(word:"thief"),VocabularyEntry(word:"无光标")]);check(store.activeWords==["thief","无光标"],"Active vocabulary")
        do {try store.saveVocabulary([VocabularyEntry(word:"C"),VocabularyEntry(word:"c")]);preconditionFailure("Duplicate accepted")}catch{}
        check(store.activeWords.count==2,"Rejected edit leaves dictionary intact")
        do {try store.saveVocabulary((0..<129).map{VocabularyEntry(word:"word\($0)")});preconditionFailure("Overflow accepted")}catch{}
        check(store.activeWords.count==2,"Overflow is never silently truncated")
        var r=SessionRecord();r.status="processing";r.raw="不会丢";r.audioFile="recover.wav";r.words=store.activeWords
        try store.update(r)
        let reload=LibraryStore();check(reload.sessions[0].status=="interrupted","Crash recovery state")
        check(reload.sessions[0].raw=="不会丢","Checkpoint preserved")
        check(reload.sessions[0].words==r.words,"Frozen vocabulary survives restart")
        r.status="completed";r.output="完成";r.cleaned="完成";r.finished=Date();r.duration=2;try store.update(r)
        var retry=r;retry.versions=["上一个版本"];try store.update(retry)
        check(Metrics.totals(store.sessions).sessions==1,"Retry does not double count")
        var cancelled=r;cancelled.status="cancelled"
        check(Metrics.totals([cancelled]).sessions==0,"Cancellation during delivery verification is not a successful input")
        var text=r;text.id=UUID();text.source="text-test";try store.update(text)
        check(Metrics.totals(store.sessions).sessions==1,"Text fixtures excluded from usage statistics")
        let calendar=Calendar(identifier:.gregorian),now=Date();var yesterday=r;yesterday.id=UUID();yesterday.created=calendar.date(byAdding:.day,value:-1,to:now)!;try store.update(yesterday)
        check(Metrics.streak(store.sessions,now:now,calendar:calendar).current==2,"Calendar streak")
        store.preferences.cleanup = .none;store.savePreferences();check(LibraryStore().preferences.cleanup == .none,"Cleanup mode survives restart")
        check(LibraryStore().vocabulary.map(\.word)==["thief","无光标"],"Vocabulary survives app replacement")
        let attrs=try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("sessions.json").path)
        check((attrs[.posixPermissions]as?Int)==0o600,"Private data file permissions")
        var wav=Data("RIFF".utf8)+Data(repeating:0,count:4)+Data("WAVEfmt ".utf8)
        func little<T:FixedWidthInteger>(_ value:T)->Data{var n=value.littleEndian;return withUnsafeBytes(of:&n){Data($0)}}
        wav+=little(UInt32(16));wav+=little(UInt16(1));wav+=little(UInt16(1));wav+=little(UInt32(16000));wav+=little(UInt32(32000));wav+=little(UInt16(2));wav+=little(UInt16(16));wav+=Data("data".utf8)+little(UInt32(0))+Data(repeating:0,count:32000)
        let broken=root.appendingPathComponent("broken.wav");try wav.write(to:broken)
        try AudioFiles.repairInterruptedWAV(broken)
        let repaired=try Data(contentsOf:broken)
        check(repaired[40..<44]==little(UInt32(32000)),"Interrupted WAV data header repaired")
        check(repaired[4..<8]==little(UInt32(repaired.count-8)),"Interrupted RIFF size repaired")
        let legacy=try JSONDecoder().decode(Preferences.self,from:Data("{\"cleanup\":\"none\",\"keepMicWarm\":true}".utf8))
        check(legacy.cleanup == .none && legacy.keepMicWarm,"Older preferences migrate without losing existing choices")
        check(legacy.dictation.matches(KeyBinding()),"New preference fields receive right Option default")
        var old=Preferences();old.dictation = .legacyDictation
        var oldJSON=try JSONSerialization.jsonObject(with:JSONEncoder().encode(old))as![String:Any];oldJSON.removeValue(forKey:"shortcutDefaultsVersion")
        let migrated=try JSONDecoder().decode(Preferences.self,from:JSONSerialization.data(withJSONObject:oldJSON))
        check(migrated.dictation.matches(KeyBinding()) && migrated.translation.matches(old.translation),"Only legacy default migrates")
        oldJSON["dictation"]=["key":100,"modifiers":0,"standalone":"","label":"F8"]
        let custom=try JSONDecoder().decode(Preferences.self,from:JSONSerialization.data(withJSONObject:oldJSON))
        check(custom.dictation.key==100 && custom.dictation.standalone.isEmpty,"Custom shortcut preserved")
        check(KeyBinding.modifierDown(key:61,flags:0x80040),"Right Option down")
        check(!KeyBinding.modifierDown(key:61,flags:0x80020),"Left Option is not right Option")
        check(!KeyBinding.modifierDown(key:61,flags:0),"Right Option release")
        check(KeyBinding.modifierDown(key:61,flags:0x80060),"Right Option while both held")
        check(OverlayLayout.compact==CGSize(width:168,height:36),"Actual compact window dimensions")
        var solo=SoloKeyState()
        check(solo.change(down:true,hold:false,blocked:false).isEmpty,"Tap waits for release")
        check(solo.change(down:false,hold:false,blocked:false)==[.down,.up],"Tap emits one toggle")
        check(solo.change(down:false,hold:false,blocked:false).isEmpty,"Duplicate release ignored")
        _=solo.change(down:true,hold:false,blocked:false);_=solo.interrupt()
        check(solo.change(down:false,hold:false,blocked:false).isEmpty,"Option chord never records")
        check(solo.change(down:true,hold:true,blocked:false)==[.down],"PTT starts without delay")
        check(solo.change(down:true,hold:true,blocked:false).isEmpty,"PTT repeat ignored")
        check(solo.change(down:false,hold:true,blocked:false)==[.up],"PTT release ends")
        _=solo.change(down:true,hold:true,blocked:false)
        check(solo.interrupt()==[.interrupt],"PTT chord cancels tentative recording")
        check(solo.change(down:false,hold:true,blocked:false).isEmpty,"Interrupted PTT cannot deliver on release")
        check(solo.change(down:true,hold:false,blocked:true).isEmpty,"Pre-held modifier blocks tap")
        check(solo.change(down:false,hold:false,blocked:false).isEmpty,"Blocked tap stays blocked")
        let corruptRoot=root.appendingPathComponent("corrupt");try FileManager.default.createDirectory(at:corruptRoot,withIntermediateDirectories:true)
        let bad=Data("{broken".utf8);try bad.write(to:corruptRoot.appendingPathComponent("preferences.json"));setenv("DIANYU_DATA_ROOT",corruptRoot.path,1)
        let damaged=LibraryStore();check(!damaged.storageError.isEmpty,"Corrupt file produces a visible recovery error")
        damaged.savePreferences();check((try? Data(contentsOf:corruptRoot.appendingPathComponent("preferences.json")))==bad,"Corrupt preferences are never overwritten with defaults")
        print("Domain checks passed:",checks)
    }
}
