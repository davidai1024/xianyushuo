import Foundation

@MainActor final class EngineClient {
    private var process:Process?
    private var input:FileHandle?
    private var buffer=Data()
    private var generation=UUID()
    private var outputHandle:FileHandle?
    private var pending:[String:CheckedContinuation<[String:Any],Error>]=[:]
    private var timers:[String:Task<Void,Never>]=[:]
    var onProgress:((String,String)->Void)?
    var onCheckpoint:((String,[String:Any])->Void)?
    var onStatus:((String)->Void)?
    var ready=false
    func start() throws {
        if process?.isRunning == true { return }
        guard let resources=Bundle.main.resourceURL else { throw AppError.message("缺少运行资源。") }
        let engine=resources.appendingPathComponent("Engine")
        let python=resources.appendingPathComponent("Runtime/bin/python3")
        guard FileManager.default.isExecutableFile(atPath:python.path) else { throw AppError.message("缺少本地运行环境，请重新安装完整应用。") }
        let p=Process(),stdin=Pipe(),stdout=Pipe();p.qualityOfService = .userInitiated
        p.executableURL=python;p.arguments=["-B","-u",engine.appendingPathComponent("worker.py").path]
        var env=ProcessInfo.processInfo.environment
        env["PYTHONPATH"]=resources.appendingPathComponent("PythonExtras").path
        env["HF_HUB_OFFLINE"]="1";env["TRANSFORMERS_OFFLINE"]="1"
        env["PYTHONUNBUFFERED"]="1";p.environment=env
        env["PYTHONDONTWRITEBYTECODE"]="1";p.environment=env
        p.standardInput=stdin;p.standardOutput=stdout
        let log=AppPaths.root.appendingPathComponent("engine.log")
        if let old=try? Data(contentsOf:log),old.count>1_000_000 { try? Data().write(to:log) }
        if !FileManager.default.fileExists(atPath:log.path){FileManager.default.createFile(atPath:log.path,contents:nil,attributes:[.posixPermissions:0o600])}
        p.standardError=try FileHandle(forWritingTo:log)
        (p.standardError as? FileHandle)?.seekToEndOfFile()
        buffer=Data();ready=false;generation=UUID();let identifier=generation
        outputHandle=stdout.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler={ [weak self] handle in
            let data=handle.availableData
            Task { @MainActor in guard self?.generation==identifier else{return};self?.consume(data) }
        }
        p.terminationHandler={ [weak self] _ in Task { @MainActor in
            guard self?.generation==identifier else{return}
            self?.ready=false;self?.process=nil;self?.failAll("本地模型进程已停止，录音和已识别文字保留，可重试。")
            self?.onStatus?("引擎已停止，可重新启动")
        } }
        try p.run();process=p;input=stdin.fileHandleForWriting
        // Queue before any real job, including the first run immediately after launch.
        let warm:[String:Any] = ["id":"prewarm","action":"prewarm","models":AppPaths.models.path]
        do {try input?.write(contentsOf:JSONSerialization.data(withJSONObject:warm)+Data([10]))}
        catch {stop();throw error}
        onStatus?("本地模型预热中")
    }
    private func consume(_ data:Data) {
        buffer.append(data)
        while let newline=buffer.firstIndex(of:10) {
            let line=buffer[..<newline];buffer.removeSubrange(...newline)
            guard let value=(try? JSONSerialization.jsonObject(with:line))as?[String:Any] else {continue}
            let event=value["event"]as?String ?? "",id=value["id"]as?String ?? ""
            if event=="ready" { ready=true;continue }
            if event=="warmed" {
                let asr=value["resident"]as?Bool ?? false,editor=value["editor_resident"]as?Bool ?? false
                onStatus?(asr ? (editor ? "识别与整理已就绪":"识别已就绪 · 整理模型未安装"):"请先下载语音识别模型");continue
            }
            if event=="warm_failed" {onStatus?("预热未完成，首次识别时将重试加载");continue}
            if event=="progress" { onProgress?(id,value["stage"]as?String ?? "正在处理");continue }
            if event=="checkpoint" { onCheckpoint?(id,value);continue }
            guard let continuation=pending.removeValue(forKey:id) else {continue}
            timers.removeValue(forKey:id)?.cancel()
            if event=="error" {continuation.resume(throwing:AppError.message(value["message"]as?String ?? "处理失败。"))}
            else {continuation.resume(returning:value)}
        }
    }
    func run(_ payload:[String:Any]) async throws -> [String:Any] {
        try start()
        let id=UUID().uuidString;var job=payload;job["id"]=id;job["models"]=AppPaths.models.path
        let bytes=try JSONSerialization.data(withJSONObject:job)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id]=continuation
            timers[id]=Task { [weak self] in
                try? await Task.sleep(nanoseconds:600_000_000_000)
                guard !Task.isCancelled else{return}
                self?.stop(reason:"本地处理超时，录音和已识别文字保留，可重试。")
            }
            do {try input?.write(contentsOf:bytes+Data([10]))}catch { pending.removeValue(forKey:id)?.resume(throwing:error);timers.removeValue(forKey:id)?.cancel() }
        }
    }
    private func failAll(_ message:String) {
        let active=pending;pending.removeAll();timers.values.forEach{$0.cancel()};timers.removeAll()
        active.values.forEach{$0.resume(throwing:AppError.message(message))}
    }
    func stop(reason:String="模型已停止，任务已保留。") {
        input?.closeFile();input=nil
        generation=UUID();outputHandle?.readabilityHandler=nil;try? outputHandle?.close();outputHandle=nil
        let old=process;process=nil;ready=false
        if old?.isRunning==true {old?.terminate()}
        failAll(reason)
    }
}
