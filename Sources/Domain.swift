import Foundation
import Combine
import AppKit

enum CleanupMode: String, Codable, CaseIterable, Identifiable {
    case none, light, structured
    var id: String { rawValue }
    var title: String { switch self { case .none: return "不整理"; case .light: return "轻整理"; case .structured: return "结构化整理" } }
    var detail: String { switch self { case .none: return "保留原始识别，词表仍参与识别。"; case .light: return "去口头赘词、重复和明确改口，补标点。"; case .structured: return "先轻整理，再按语义分段；不总结、不补写。" } }
}
struct KeyBinding: Codable, Equatable {
    var key: UInt32 = 61
    var modifiers: UInt32 = 0
    var standalone: String = "rightOption"
    var label: String = "右侧 Option"
    static var legacyDictation:KeyBinding {KeyBinding(key:49,modifiers:6144,standalone:"",label:"⌃⌥Space")}
    func matches(_ other:KeyBinding)->Bool{key==other.key && modifiers==other.modifiers && standalone==other.standalone}
    var keycaps:[String] {
        if standalone=="rightOption"{return ["右侧","⌥"]}
        if standalone=="fn"{return ["Fn"]}
        var values:[String]=[]
        for (mask,glyph) in [(UInt32(4096),"⌃"),(2048,"⌥"),(512,"⇧"),(256,"⌘")] where modifiers & mask != 0 {values.append(glyph)}
        var main=label;for glyph in ["⌃","⌥","⇧","⌘"]{main=main.replacingOccurrences(of:glyph,with:"")}
        values.append(main.isEmpty ? "Key \(key)":main);return values
    }
    static func modifierDown(key:UInt32,flags:UInt)->Bool {
        if key==61 {
            // Public NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK from IOLLEvent.h.
            return flags & 0x60 != 0 ? flags & 0x40 != 0 : flags & NSEvent.ModifierFlags.option.rawValue != 0
        }
        return key==63 && flags & NSEvent.ModifierFlags.function.rawValue != 0
    }
}
struct Preferences: Codable, Equatable {
    var cleanup: CleanupMode = .light
    var hideDockIcon = false
    var preserveHeadphoneControls = true
    var keepMicWarm = false
    var muteWhileRecording = true
    var streamWhileRecording = true
    var holdToTalk = false
    var microphoneUID = ""
    var preferBuiltIn = false
    var autoPaste = true
    var keepClipboard = true
    var launchAtLogin = false
    var dictation = KeyBinding()
    var translation = KeyBinding(key: 49, modifiers: 6656, standalone: "", label: "⌃⌥⇧Space")
    var retentionDays = 30
    var updateFeed = ""
    var shortcutDefaultsVersion=2
    init(){}
    private enum CodingKeys:String,CodingKey {case cleanup,hideDockIcon,preserveHeadphoneControls,keepMicWarm,muteWhileRecording,streamWhileRecording,holdToTalk,microphoneUID,preferBuiltIn,autoPaste,keepClipboard,launchAtLogin,dictation,translation,retentionDays,updateFeed,shortcutDefaultsVersion}
    init(from decoder:Decoder)throws {
        self.init();let c=try decoder.container(keyedBy:CodingKeys.self)
        cleanup=CleanupMode(rawValue:try c.decodeIfPresent(String.self,forKey:.cleanup) ?? "light") ?? .light
        hideDockIcon=try c.decodeIfPresent(Bool.self,forKey:.hideDockIcon) ?? hideDockIcon
        preserveHeadphoneControls=try c.decodeIfPresent(Bool.self,forKey:.preserveHeadphoneControls) ?? preserveHeadphoneControls
        keepMicWarm=try c.decodeIfPresent(Bool.self,forKey:.keepMicWarm) ?? keepMicWarm
        muteWhileRecording=try c.decodeIfPresent(Bool.self,forKey:.muteWhileRecording) ?? muteWhileRecording
        streamWhileRecording=try c.decodeIfPresent(Bool.self,forKey:.streamWhileRecording) ?? streamWhileRecording
        holdToTalk=try c.decodeIfPresent(Bool.self,forKey:.holdToTalk) ?? holdToTalk
        microphoneUID=try c.decodeIfPresent(String.self,forKey:.microphoneUID) ?? microphoneUID
        preferBuiltIn=try c.decodeIfPresent(Bool.self,forKey:.preferBuiltIn) ?? preferBuiltIn
        autoPaste=try c.decodeIfPresent(Bool.self,forKey:.autoPaste) ?? autoPaste
        keepClipboard=try c.decodeIfPresent(Bool.self,forKey:.keepClipboard) ?? keepClipboard
        launchAtLogin=try c.decodeIfPresent(Bool.self,forKey:.launchAtLogin) ?? launchAtLogin
        dictation=try c.decodeIfPresent(KeyBinding.self,forKey:.dictation) ?? dictation
        translation=try c.decodeIfPresent(KeyBinding.self,forKey:.translation) ?? translation
        retentionDays=try c.decodeIfPresent(Int.self,forKey:.retentionDays) ?? retentionDays
        updateFeed=try c.decodeIfPresent(String.self,forKey:.updateFeed) ?? updateFeed
        if (try c.decodeIfPresent(Int.self,forKey:.shortcutDefaultsVersion) ?? 1)<2,dictation.matches(.legacyDictation){dictation=KeyBinding()}
        shortcutDefaultsVersion=2
    }
}
enum OverlayLayout {
    static let compact=CGSize(width:168,height:36)
    static let expanded=CGSize(width:280,height:148)
    static let verifiedHoldSeconds=0.25
    static func processingTitle(_ stage:String)->String{
        if ["整理","段落","填入"].contains(where:stage.contains){return "正在完成"}
        return stage
    }
    static func dismissDelay(phase:String,delivery:String,cancelled:Bool=false)->Double?{
        guard phase=="result" else{return nil}
        if delivery=="verified"{return verifiedHoldSeconds}
        if cancelled{return 0.7}
        if delivery=="clipboard" || delivery=="saved"{return 2}
        return nil
    }
    static func capsuleFrame(in visible:CGRect)->CGRect{CGRect(x:visible.midX-compact.width/2,y:visible.minY+14,width:compact.width,height:compact.height)}
}
struct VocabularyEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var word: String
    var enabled = true
}
enum VocabularyRules {
    static let maxImportBytes=1_048_576
    static func key(_ value:String)->String{value.trimmingCharacters(in:.whitespacesAndNewlines).precomposedStringWithCompatibilityMapping.folding(options:.caseInsensitive,locale:Locale(identifier:"en_US_POSIX"))}
    static func validated(_ value:String)throws->String{
        let word=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !word.isEmpty else{throw AppError.message("词条不能为空。")}
        guard word.rangeOfCharacter(from:.newlines)==nil else{throw AppError.message("每个词条只能占一行。")}
        guard word.unicodeScalars.count<=80 else{throw AppError.message("每个词条最多80个 Unicode 码点，当前为\(word.unicodeScalars.count)个。")}
        return word
    }
    static func imported(_ data:Data,json:Bool,existing:[VocabularyEntry])throws->(values:[VocabularyEntry],added:Int,skipped:Int){
        guard data.count<=maxImportBytes else{throw AppError.message("导入文件不能超过1 MiB。")}
        let raw:[String]
        if json{guard let decoded=try? JSONDecoder().decode([String].self,from:data)else{throw AppError.message("JSON格式无效，需要由词条字符串组成的数组。")};raw=decoded}
        else{guard let text=String(data:data,encoding:.utf8)else{throw AppError.message("TXT文件需使用UTF-8编码。")};raw=text.components(separatedBy:.newlines).filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}}
        var values=existing,seen=Set(existing.map{key($0.word)}),added=0,skipped=0
        for candidate in raw{
            let word=try validated(candidate)
            if !seen.insert(key(word)).inserted{skipped+=1;continue}
            values.append(VocabularyEntry(word:word));added+=1
        }
        guard values.count<=128 else{throw AppError.message("导入后会有\(values.count)项，超过128项；本批次未保存。")}
        return(values,added,skipped)
    }
}
struct SessionRecord: Codable, Identifiable {
    var id = UUID()
    var created = Date()
    var finished: Date?
    var status = "recording"
    var audioFile = ""
    var duration = 0.0
    var cleanup: CleanupMode = .light
    var translate = false
    var words: [String] = []
    var raw = ""
    var cleaned = ""
    var translated = ""
    var output = ""
    var error = ""
    var delivery = ""
    var metadata = ""
    var processingSeconds = 0.0
    var source = "microphone"
    var versions: [String] = []
    var counted: Bool { status == "completed" && finished != nil && !output.isEmpty && source == "microphone" }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}
enum AppPaths {
    static var root: URL {
        if let override = ProcessInfo.processInfo.environment["DIANYU_DATA_ROOT"] { return URL(fileURLWithPath: override) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dianyu")
    }
    static var audio: URL { root.appendingPathComponent("Recordings") }
    static var models: URL { root.appendingPathComponent("models") }
    static func prepare() throws {
        for path in [root,audio,models] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(value); try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func read<T: Decodable>(_ type: T.Type, name: String, fallback: T) throws -> T {
        let path=root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: path.path) else { return fallback }
        return try JSONDecoder().decode(type, from: Data(contentsOf: path))
    }
}
enum Metrics {
    static func count(_ text: String) -> Int {
        let pattern = "[\\p{Han}]|[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*"
        return (try? NSRegularExpression(pattern:pattern).numberOfMatches(in:text,range:NSRange(text.startIndex...,in:text))) ?? 0
    }
    static func totals(_ records: [SessionRecord]) -> (words: Int, sessions: Int, seconds: Double, wpm: Int) {
        let valid=records.filter(\.counted)
        let words=valid.reduce(0){$0+count($1.cleaned.isEmpty ? $1.raw : $1.cleaned)}
        let seconds=valid.reduce(0){$0+$1.duration}
        return (words,valid.count,seconds,seconds>0 ? Int(Double(words)*60/seconds):0)
    }
    static func streak(_ records: [SessionRecord], now: Date=Date(), calendar: Calendar = .current) -> (current:Int,longest:Int) {
        let days=Set(records.filter(\.counted).map{calendar.startOfDay(for:$0.created)})
        let ordered=days.sorted();var longest=0,run=0;var prior:Date?
        for day in ordered { run = prior.flatMap{calendar.date(byAdding:.day,value:1,to:$0)} == day ? run+1 : 1;longest=max(longest,run);prior=day }
        var cursor=calendar.startOfDay(for:now),current=0
        if !days.contains(cursor) { cursor=calendar.date(byAdding:.day,value:-1,to:cursor)! }
        while days.contains(cursor) { current+=1;cursor=calendar.date(byAdding:.day,value:-1,to:cursor)! }
        return (current,longest)
    }
}
@MainActor final class LibraryStore: ObservableObject {
    @Published var preferences=Preferences()
    @Published var vocabulary:[VocabularyEntry]=[]
    @Published var sessions:[SessionRecord]=[]
    @Published var storageError=""
    init() {
        do {
            try AppPaths.prepare()
            preferences=try AppPaths.read(Preferences.self,name:"preferences.json",fallback:Preferences())
            vocabulary=try AppPaths.read([VocabularyEntry].self,name:"vocabulary.json",fallback:[])
            sessions=try AppPaths.read([SessionRecord].self,name:"sessions.json",fallback:[])
            for i in sessions.indices where ["recording","processing"].contains(sessions[i].status) {
                if sessions[i].status=="recording",!sessions[i].audioFile.isEmpty{try? AudioFiles.repairInterruptedWAV(AppPaths.audio.appendingPathComponent(sessions[i].audioFile))}
                sessions[i].status="interrupted";sessions[i].error="上次任务中断，已保存的录音和文字可恢复。"
            }
            try persistSessions()
        } catch { storageError="本地资料读取失败，未覆盖原文件：\(error.localizedDescription)" }
    }
    var activeWords:[String] { vocabulary.filter(\.enabled).map(\.word) }
    func savePreferences() { guard storageError.isEmpty else{return};do { try AppPaths.write(preferences,to:AppPaths.root.appendingPathComponent("preferences.json")) } catch { storageError=error.localizedDescription } }
    func saveVocabulary(_ values:[VocabularyEntry]) throws {
        guard storageError.isEmpty else{throw AppError.message(storageError)}
        guard values.count<=128 else { throw AppError.message("词表最多128项，超出时请先精简；不会静默丢弃条目。") }
        var seen=Set<String>(),normalized=values
        for i in normalized.indices {
            let word=try VocabularyRules.validated(normalized[i].word)
            guard seen.insert(VocabularyRules.key(word)).inserted else{throw AppError.message("词条重复，请编辑原词条或使用其他写法。")}
            normalized[i].word=word
        }
        try AppPaths.write(normalized,to:AppPaths.root.appendingPathComponent("vocabulary.json"));vocabulary=normalized
    }
    func persistSessions() throws { try AppPaths.write(sessions,to:AppPaths.root.appendingPathComponent("sessions.json")) }
    func update(_ value:SessionRecord) throws {
        guard storageError.isEmpty else {throw AppError.message(storageError)}
        var next=sessions
        if let index=next.firstIndex(where:{$0.id==value.id}) { next[index]=value } else { next.insert(value,at:0) }
        try AppPaths.write(next,to:AppPaths.root.appendingPathComponent("sessions.json"));sessions=next
    }
    func expireAudio() {
        guard preferences.retentionDays>0 else{return}
        let cutoff=Date().addingTimeInterval(-Double(preferences.retentionDays)*86400)
        for r in sessions where r.created<cutoff && r.status=="completed" && !r.audioFile.isEmpty {
            // Only completed audio expires; incomplete tasks remain recoverable.
            try? FileManager.default.removeItem(at:AppPaths.audio.appendingPathComponent(r.audioFile))
        }
    }
}
