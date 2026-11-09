import Foundation

/// Explicit, multi-GB integration test. Uses the actual downloader/manager in a
/// separate data root; never reads or replaces the user's installed models.
@main struct ModelFullDownloadTests {
    @MainActor static func main()async throws{
        let fm=FileManager.default
        let root:URL
        if let resume=ProcessInfo.processInfo.environment["DIANYU_FULL_DOWNLOAD_ROOT"]{
            let candidate=URL(fileURLWithPath:resume).standardizedFileURL
            precondition(candidate.deletingLastPathComponent().resolvingSymlinksInPath()==fm.temporaryDirectory.resolvingSymlinksInPath() && candidate.lastPathComponent.hasPrefix("DianyuFullDownload-"))
            root=candidate
        }else{root=fm.temporaryDirectory.appendingPathComponent("DianyuFullDownload-"+UUID().uuidString)}
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare()
        defer{try? fm.removeItem(at:root)}
        var checks=0
        func check(_ pass:Bool,_ message:String){precondition(pass,message);checks+=1;print("PASS",message);fflush(stdout)}
        let specs=try ModelCatalog.load(),manifest=try ModelResources.manifest()
        let manager=ModelDownloads.shared,app=AppState.shared
        check(app.store.sessions.isEmpty && app.store.vocabulary.isEmpty,"Isolated fresh install")
        check(ModelCatalog.missing(cleanup:.none,translate:false)==[specs[0].id],"ASR-only has no optional download")
        // Prefetch explicitly requested optional roles concurrently into their
        // own staging folders. The real manager still installs each one idle.
        let tickets=Dictionary(uniqueKeysWithValues:specs.filter{$0.role != "asr"}.map{($0.id,ModelDownloadTicket())})
        defer{for ticket in tickets.values{ticket.cancel()}}
        let prefetch=Dictionary(uniqueKeysWithValues:specs.filter{$0.role != "asr"}.map{spec in
            (spec.id,Task.detached(priority:.utility){try ModelFetch.download(spec:spec,files:manifest[spec.id]!,root:root,mirror:true,ticket:tickets[spec.id]!)})
        })
        for spec in specs{
            let files=manifest[spec.id]!,start=Date()
            if let fetch=prefetch[spec.id]{_ = try await fetch.value}
            manager.mirror=true;manager.start(spec)
            // Interrupt the ASR's real HTTP transfer, not an artificial sleep.
            if spec.role=="asr"{
                let deadline=Date().addingTimeInterval(180)
                while manager.downloading && Date()<deadline{
                    if ModelFetch.progress(spec.id,files:files,root:root)>0.002{break}
                    try await Task.sleep(nanoseconds:200_000_000)
                }
                check(manager.downloading,"Real ASR transfer started")
                manager.pause()
                while manager.downloading{try await Task.sleep(nanoseconds:100_000_000)}
                let partial=ModelFetch.progress(spec.id,files:files,root:root)
                check(partial>0 && partial<1,"Pause retained downloaded bytes")
                check(!ModelCatalog.installed(spec.id),"Partial weights never installed")
                manager.start(spec)
            }
            var last=Date.distantPast
            while manager.downloading{
                if Date().timeIntervalSince(last)>15{print(spec.role,String(format:"%.1f%%",manager.fraction*100));fflush(stdout);last=Date()}
                try await Task.sleep(nanoseconds:200_000_000)
            }
            guard ModelCatalog.installed(spec.id)else{throw AppError.message("Full model integration failed: "+manager.status)}
            try await Task.detached{try ModelResources.validate(AppPaths.models,manifest:[spec.id:files])}.value
            check(true,"Full "+spec.role+" weight sizes/SHA256, idle installation and hot enable verified")
            print(spec.role,"bytes",files.reduce(Int64(0)){$0+$1.bytes},"seconds",Date().timeIntervalSince(start));fflush(stdout)
            if spec.role=="asr"{check(ModelCatalog.missing(cleanup:.light,translate:true).count==2,"Optional models still absent after base installation")}
        }
        check(ModelCatalog.missing(cleanup:.structured,translate:true).isEmpty,"All explicitly requested roles installed")
        check(app.store.sessions.isEmpty && app.store.vocabulary.isEmpty,"No history or vocabulary created by downloads")
        print("Full model download checks passed:",checks);fflush(stdout)
    }
}
