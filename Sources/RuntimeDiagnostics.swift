import Foundation

/// Bounded, local lifecycle breadcrumbs. Never include transcripts, clipboard,
/// focused-app content, audio, vocabulary entries or permission databases.
enum RuntimeDiagnostics {
    private static let lock=NSLock()
    private static let limit=65_536
    static func event(_ name:String,field:String=""){
        lock.lock();defer{lock.unlock()}
        let root=AppPaths.root
        guard FileManager.default.fileExists(atPath:root.path) else{return}
        let path=root.appendingPathComponent("lifecycle.jsonl")
        let value:[String:Any]=["time":Date().timeIntervalSince1970,"uptime":ProcessInfo.processInfo.systemUptime,"event":name,"field":field,"pid":ProcessInfo.processInfo.processIdentifier,"version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString")as?String ?? "test","build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion")as?String ?? "test","main_thread":Thread.isMainThread,"run_loop_mode":RunLoop.current.currentMode?.rawValue ?? "none"]
        guard let row=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else{return}
        var data=(try? Data(contentsOf:path)) ?? Data()
        if data.count+row.count+1>limit {
            let suffix=data.suffix(limit/2)
            if let newline=suffix.firstIndex(of:10){data=Data(suffix.suffix(from:suffix.index(after:newline)))}else{data=Data()}
        }
        data.append(row);data.append(10)
        do{try data.write(to:path,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)}catch{}
    }
}
