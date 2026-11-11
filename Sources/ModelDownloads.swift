import Foundation
import Combine
import Darwin

struct ModelSpec:Decodable,Identifiable {
    let id:String,title:String,role:String,repo:String,detail:String,revision:String
}
enum ModelCatalog {
    static func load()throws->[ModelSpec]{
        guard let url=Bundle.main.url(forResource:"ModelSources",withExtension:"json")else{throw AppError.message("缺少模型来源清单。")}
        let specs=try JSONDecoder().decode([ModelSpec].self,from:Data(contentsOf:url))
        guard specs.count==3,Set(specs.map(\.id)).count==3,specs.allSatisfy({$0.repo.range(of:#"^mlx-community/[A-Za-z0-9_.-]+$"#,options:.regularExpression) != nil && !$0.id.contains("/") && !$0.id.contains("..") && $0.revision.range(of:#"^[a-f0-9]{40}$"#,options:.regularExpression) != nil})else{throw AppError.message("模型来源清单无效。")}
        return specs
    }
    static func installed(_ id:String,root:URL=AppPaths.models)->Bool{
        guard let files=try? ModelResources.manifest()[id] else{return false}
        return installed(files,in:root.appendingPathComponent(id))
    }
    static func installed(_ files:[ModelFile],in folder:URL)->Bool{
        guard !files.isEmpty else{return false}
        return files.allSatisfy{file in
            let path=folder.appendingPathComponent(file.path)
            return ((try? FileManager.default.attributesOfItem(atPath:path.path)[.size])as?NSNumber)?.int64Value==file.bytes
        }
    }
    static func missing(cleanup:CleanupMode,translate:Bool,provider:CleanupProvider = .local,root:URL=AppPaths.models)->[String]{
        var names=["Qwen3-ASR-1.7B-8bit"]
        if cleanup != .none && provider == .local{names.append("Qwen3-1.7B-4bit")}
        if translate{names.append("Hy-MT2-1.8B-4bit")}
        return names.filter{!installed($0,root:root)}
    }
    static func sourceURL(_ spec:ModelSpec,file:String,mirror:Bool)->URL {
        var allowed=CharacterSet.urlPathAllowed;allowed.remove(charactersIn:"?#")
        let path=file.addingPercentEncoding(withAllowedCharacters:allowed)!
        return URL(string:mirror ? "https://modelscope.cn/models/\(spec.repo)/resolve/master/\(path)":"https://huggingface.co/\(spec.repo)/resolve/\(spec.revision)/\(path)")!
    }
}

/// The network process writes only private staging files. No audio/text is sent.
/// A terminated curl leaves a resumable partial file; integrity is checked before use.
final class ModelDownloadTicket:@unchecked Sendable {
    private let lock=NSLock()
    private var cancelled=false
    private var processes:[ObjectIdentifier:Process]=[:]
    var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
    func cancel(){
        lock.lock();cancelled=true;let current=Array(processes.values);lock.unlock()
        // A child may finish between isRunning and cancellation. POSIX signalling
        // reports ESRCH rather than raising an Objective-C task-state exception.
        for process in current where process.isRunning{let pid=process.processIdentifier;if pid>0{_ = Darwin.kill(pid,SIGTERM)}}
    }
    func run(_ process:Process)throws {
        // Protect the launch/cancel boundary: cancellation can never miss a process
        // that has attached but has not yet begun running.
        lock.lock()
        guard !cancelled else{lock.unlock();throw CancellationError()}
        let key=ObjectIdentifier(process);processes[key]=process
        do{try process.run()}catch{processes.removeValue(forKey:key);lock.unlock();throw error}
        lock.unlock();process.waitUntilExit();lock.lock();processes.removeValue(forKey:key);lock.unlock()
        if isCancelled{throw CancellationError()}
    }
}

enum ModelFetch {
    static func bytes(_ url:URL)->Int64{((try? FileManager.default.attributesOfItem(atPath:url.path)[.size])as?NSNumber)?.int64Value ?? 0}
    static func verified(_ url:URL,_ file:ModelFile)->Bool{bytes(url)==file.bytes && (try? ModelResources.sha256(url))==file.sha256}
    static func directory(_ id:String,root:URL)->URL{root.appendingPathComponent("ModelDownloads").appendingPathComponent(id)}
    static func progress(_ id:String,files:[ModelFile],root:URL)->Double{
        let folder=directory(id,root:root),total=files.reduce(Int64(0)){$0+$1.bytes}
        let done=files.reduce(Int64(0)){sum,file in
            let path=folder.appendingPathComponent(file.path)
            let ranges=path.appendingPathExtension("ranges")
            var pieces:[String:Int64]=[:]
            for piece in (try? FileManager.default.contentsOfDirectory(at:ranges,includingPropertiesForKeys:nil)) ?? [] where ["part","partial"].contains(piece.pathExtension){
                let key=piece.deletingPathExtension().lastPathComponent
                guard let index=Int(key),index>=0 else{continue}
                pieces[key]=max(pieces[key] ?? 0,min(16*1024*1024,bytes(piece)))
            }
            let chunks=pieces.values.reduce(Int64(0),+)
            return sum+min(file.bytes,max(chunks,max(bytes(path),bytes(path.appendingPathExtension("partial")))))
        }
        return total>0 ? min(1,Double(done)/Double(total)):0
    }
    static func download(spec:ModelSpec,files:[ModelFile],root:URL,mirror:Bool,ticket:ModelDownloadTicket)throws->URL {
        let folder=directory(spec.id,root:root)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        // Each partial belongs to a particular signed catalog hash, never a mutable
        // remote 'latest' response. Changed catalogs restart only affected files.
        for file in files.sorted(by:{$0.bytes<$1.bytes}){
            if ticket.isCancelled{throw CancellationError()}
            try ModelResources.validatePath(file.path)
            let target=folder.appendingPathComponent(file.path),partial=target.appendingPathExtension("partial"),marker=target.appendingPathExtension("sha256")
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            if verified(target,file){try? FileManager.default.removeItem(at:target.appendingPathExtension("ranges"));continue}
            if (try? String(contentsOf:marker,encoding:.utf8)) != file.sha256{
                try? FileManager.default.removeItem(at:partial)
                try? FileManager.default.removeItem(at:target.appendingPathExtension("ranges"))
                try file.sha256.write(to:marker,atomically:true,encoding:.utf8)
            }
            if bytes(partial)>=file.bytes && !verified(partial,file){try FileManager.default.removeItem(at:partial)}
            if verified(partial,file){try? FileManager.default.removeItem(at:target);try FileManager.default.moveItem(at:partial,to:target);try? FileManager.default.removeItem(at:target.appendingPathExtension("ranges"));continue}
            let remaining=max(0,file.bytes-bytes(partial))
            if let available=(try? folder.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,available<remaining+64*1024*1024{throw AppError.message("磁盘空间不足，请腾出空间后继续下载。")}
            // Only public pinned-catalog model URLs are used, with normal TLS checks.
            let url=ModelCatalog.sourceURL(spec,file:file.path,mirror:mirror)
            guard url.scheme=="https" else{throw AppError.message("模型下载地址必须使用 HTTPS。")}
            func transfer(resume:Bool)throws->Int32{
                let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/curl")
                process.arguments=["--silent","--show-error","--fail","--location","--proto","=https","--proto-redir","=https","--connect-timeout","20","--speed-limit","1024","--speed-time","60","--retry","2","--max-filesize",String(file.bytes),"--output",partial.path]+(resume ? ["--continue-at","-"]:[])+[url.absoluteString]
                process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
                try ticket.run(process);return process.terminationStatus
            }
            let usedRanges=try file.bytes>=64*1024*1024 ? ranged(url:url,file:file,partial:partial,ticket:ticket):false
            var code=usedRanges ? 0:try transfer(resume:bytes(partial)>0)
            if code==33 || code==36{ // Server declined byte-range continuation.
                try? FileManager.default.removeItem(at:partial);code=try transfer(resume:false)
            }
            if ticket.isCancelled{throw CancellationError()}
            guard code==0 else{throw AppError.message("下载未完成（\(code)）。已保留进度，可重试或切换下载源。")}
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:partial.path)
            guard verified(partial,file)else{
                // A bad complete response must not become a permanently resumable
                // invalid file, and must never displace a working installed model.
                try? FileManager.default.removeItem(at:partial)
                try? FileManager.default.removeItem(at:target.appendingPathExtension("ranges"))
                throw AppError.message("下载文件版本或校验不符，现有模型未更改。请切换下载源或更新应用。")
            }
            try? FileManager.default.removeItem(at:target);try FileManager.default.moveItem(at:partial,to:target)
            try? FileManager.default.removeItem(at:target.appendingPathExtension("ranges"))
        }
        try ModelResources.validate(folder.deletingLastPathComponent(),manifest:[spec.id:files])
        return folder
    }
    /// Bounded byte ranges avoid one slow connection holding up a multi-GB model.
    /// Completed ranges survive pause/restart. Every response must prove its exact
    /// Content-Range; the original full-file SHA256 remains the installation gate.
    private static func ranged(url:URL,file:ModelFile,partial:URL,ticket:ModelDownloadTicket)throws->Bool{
        let fm=FileManager.default,chunk:Int64=16*1024*1024
        let folder=partial.deletingPathExtension().appendingPathExtension("ranges")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let count=Int((file.bytes+chunk-1)/chunk)
        // Import complete ranges from an older single-stream partial, preserving
        // its bytes until all range requests succeed (including fallback cases).
        let oldBytes=bytes(partial)
        if oldBytes>=chunk{
            let input=try FileHandle(forReadingFrom:partial);defer{try? input.close()}
            for i in 0..<count{
                let start=Int64(i)*chunk,size=min(chunk,file.bytes-start),target=folder.appendingPathComponent("\(i).part")
                if bytes(target)==size || start+size>oldBytes{continue}
                try input.seek(toOffset:UInt64(start));guard let data=try input.read(upToCount:Int(size)),data.count==Int(size)else{break}
                try data.write(to:target,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
            }
        }
        if let available=(try? folder.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage,available<file.bytes*2+64*1024*1024{throw AppError.message("磁盘空间不足，分段下载需要额外的校验空间。")}
        let queue=NSLock();var next=0,failure:Error?,unsupported=false
        DispatchQueue.concurrentPerform(iterations:8){_ in
            while true{
                queue.lock();let index=next;next+=1;let stop=failure != nil || unsupported || index>=count;queue.unlock()
                if stop || ticket.isCancelled{return}
                let start=Int64(index)*chunk,end=min(file.bytes,start+chunk)-1,size=end-start+1
                let target=folder.appendingPathComponent("\(index).part"),temp=folder.appendingPathComponent("\(index).partial"),headers=folder.appendingPathComponent("\(index).headers")
                if bytes(target)==size{continue}
                do{
                    let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/curl")
                    process.arguments=["--silent","--show-error","--fail","--location","--proto","=https","--proto-redir","=https","--connect-timeout","20","--speed-limit","1024","--speed-time","60","--retry","2","--range","\(start)-\(end)","--max-filesize",String(size),"--dump-header",headers.path,"--output",temp.path,url.absoluteString]
                    process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
                    try ticket.run(process)
                    let content=(try? String(contentsOf:headers,encoding:.utf8)) ?? ""
                    let range=content.components(separatedBy:.newlines).last{ $0.lowercased().hasPrefix("content-range:") }?.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                    let exact="content-range: bytes \(start)-\(end)/\(file.bytes)"
                    if process.terminationStatus==63 || range != exact{
                        queue.lock();unsupported=true;queue.unlock();continue
                    }
                    guard process.terminationStatus==0,bytes(temp)==size else{throw AppError.message("分段下载未完成，已保留完成的进度，可重试。")}
                    try? fm.removeItem(at:target);try fm.moveItem(at:temp,to:target);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)
                }catch{queue.lock();if failure==nil{failure=error};queue.unlock()}
                try? fm.removeItem(at:headers)
            }
        }
        if ticket.isCancelled{throw CancellationError()}
        if let failure{throw failure}
        if unsupported{return false}
        // Full assembly is off the main actor and only starts once all ranges
        // have been received. A crash leaves the ranges available for reassembly.
        fm.createFile(atPath:partial.path,contents:nil,attributes:[.posixPermissions:0o600])
        let output=try FileHandle(forWritingTo:partial);defer{try? output.close()};try output.truncate(atOffset:0)
        for i in 0..<count{
            if ticket.isCancelled{throw CancellationError()}
            let source=folder.appendingPathComponent("\(i).part"),size=min(chunk,file.bytes-Int64(i)*chunk)
            guard bytes(source)==size else{throw AppError.message("分段下载文件不完整，请继续下载。")}
            let input=try FileHandle(forReadingFrom:source)
            do{while let data=try input.read(upToCount:1_048_576),!data.isEmpty{if ticket.isCancelled{throw CancellationError()};try output.write(contentsOf:data)};try input.close()}catch{try? input.close();throw error}
        }
        try output.synchronize();return true
    }
}

@MainActor final class ModelDownloads:ObservableObject {
    static let shared=ModelDownloads()
    struct Overview:Equatable {
        let installed:Bool
        let bytes:Int64
        let hasPartial:Bool
    }
    @Published var activeID:String?
    @Published var fraction=0.0
    @Published var status="模型按需下载，不会自动下载翻译模型。"
    @Published var revision=0
    @Published var mirror=true
    @Published private(set) var overview:[String:Overview]=[:]
    private var ticket:ModelDownloadTicket?
    private var timer:Timer?
    private var generation=UUID()
    let specs=(try? ModelCatalog.load()) ?? []
    var downloading:Bool{activeID != nil}
    func refreshOverview() async {
        let ids=specs.map(\.id),root=AppPaths.root,models=AppPaths.models,expectedRevision=revision
        let next=await Task.detached(priority:.utility){()->[String:Overview] in
            let manifest=(try? ModelResources.manifest()) ?? [:]
            var result:[String:Overview]=[:]
            for id in ids{
                let files=manifest[id] ?? []
                let installed=ModelCatalog.installed(files,in:models.appendingPathComponent(id))
                result[id]=Overview(installed:installed,bytes:files.reduce(0){$0+$1.bytes},
                                    hasPartial:!installed && ModelFetch.progress(id,files:files,root:root)>0)
            }
            return result
        }.value
        guard !Task.isCancelled,revision==expectedRevision,next != overview else{return}
        overview=next
    }
    func start(_ spec:ModelSpec){
        guard !downloading else{return}
        do{
            guard let files=try ModelResources.manifest()[spec.id]else{throw AppError.message("缺少该模型的校验清单。")}
            let next=ModelDownloadTicket(),owner=UUID(),root=AppPaths.root,useMirror=mirror
            ticket=next;generation=owner;activeID=spec.id;fraction=ModelFetch.progress(spec.id,files:files,root:root);status="正在下载\(spec.title)，可暂停后继续。"
            timer=Timer.scheduledTimer(withTimeInterval:0.3,repeats:true){[weak self]_ in Task{@MainActor in
                guard let self,self.generation==owner else{return};self.fraction=ModelFetch.progress(spec.id,files:files,root:root)
            }}
            Task{
                do{
                    let folder=try await Task.detached(priority:.utility){try ModelFetch.download(spec:spec,files:files,root:root,mirror:useMirror,ticket:next)}.value
                    guard generation==owner,!next.isCancelled else{throw CancellationError()}
                    fraction=1;status="下载与校验完成，等待当前输入结束后启用。"
                    let app=AppState.shared
                    while app.busy{try await Task.sleep(nanoseconds:250_000_000);if next.isCancelled{throw CancellationError()}}
                    guard generation==owner,!next.isCancelled else{throw CancellationError()}
                    app.resourcesBusy=true;app.engine.stop()
                    do{try ModelResources.installModel(from:folder,name:spec.id,files:files)}catch{app.resourcesBusy=false;app.startServices();throw error}
                    app.resourcesBusy=false;app.startServices();revision+=1;status="\(spec.title)已启用，无需重启应用。"
                }catch is CancellationError{if generation==owner{status="下载已暂停，已下载的部分保留。"}}
                catch{if generation==owner{status=error.localizedDescription}}
                if generation==owner{timer?.invalidate();timer=nil;activeID=nil;ticket=nil;revision+=1}
            }
        }catch{status=error.localizedDescription}
    }
    func pause(){guard activeID != nil else{return};ticket?.cancel();status="正在暂停，下载进度会保留。"}
}
