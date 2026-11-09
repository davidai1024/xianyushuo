import Foundation

@main struct ModelDownloadTests {
    @MainActor static func main()async throws{
        var checks=0
        func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("DianyuModels-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1)
        defer{try? fm.removeItem(at:root)}
        try AppPaths.prepare()
        let catalog=try ModelCatalog.load(),manifest=try ModelResources.manifest()
        check(catalog.count==3,"Three independent model roles")
        check(ModelCatalog.missing(cleanup:.none,translate:false).count==1,"Base dictation needs ASR only")
        check(ModelCatalog.missing(cleanup:.light,translate:false).count==2,"Cleanup optional, no MT")
        check(ModelCatalog.missing(cleanup:.structured,translate:true).count==3,"Translation explicit")
        for spec in catalog{
            check(ModelCatalog.sourceURL(spec,file:"config.json",mirror:false).path.contains(spec.revision),"HF pinned revision")
            check(ModelCatalog.sourceURL(spec,file:"config.json",mirror:true).host=="modelscope.cn","Public mirror only")
        }
        for path in ["../escape","/absolute","x/../../bad","x\\bad"]{
            do{try ModelResources.validatePath(path);fatalError("Unsafe path accepted")}catch{checks+=1}
        }
        // Exercise actual HTTPS + byte-range continuation against all 3 providers'
        // repositories using small config files, never multi-GB weights.
        for spec in catalog{
            let file=manifest[spec.id]!.first{$0.path=="config.json"}!
            let first=try ModelFetch.download(spec:spec,files:[file],root:root,mirror:false,ticket:ModelDownloadTicket())
            let leftover=first.appendingPathComponent(file.path).appendingPathExtension("ranges")
            try fm.createDirectory(at:leftover,withIntermediateDirectories:true)
            try Data(repeating:0,count:20).write(to:leftover.appendingPathComponent("0.part"))
            _ = try ModelFetch.download(spec:spec,files:[file],root:root,mirror:false,ticket:ModelDownloadTicket())
            check(!fm.fileExists(atPath:leftover.path),"A verified cached file clears interrupted range duplicates")
            let complete=try Data(contentsOf:first.appendingPathComponent(file.path))
            try fm.removeItem(at:first.appendingPathComponent(file.path))
            try complete.write(to:first.appendingPathComponent(file.path+".partial"))
            try fm.createDirectory(at:leftover,withIntermediateDirectories:true)
            try Data(repeating:0,count:20).write(to:leftover.appendingPathComponent("0.part"))
            _ = try ModelFetch.download(spec:spec,files:[file],root:root,mirror:false,ticket:ModelDownloadTicket())
            check(!fm.fileExists(atPath:leftover.path),"A verified complete partial clears range duplicates before installation")
            let prefix=try Data(contentsOf:first.appendingPathComponent(file.path)).prefix(100)
            try fm.removeItem(at:first)
            let folder=ModelFetch.directory(spec.id,root:root)
            try fm.createDirectory(at:folder,withIntermediateDirectories:true)
            try Data(prefix).write(to:folder.appendingPathComponent(file.path+".partial"))
            try file.sha256.write(to:folder.appendingPathComponent(file.path+".sha256"),atomically:true,encoding:.utf8)
            let resumed=try ModelFetch.download(spec:spec,files:[file],root:root,mirror:true,ticket:ModelDownloadTicket())
            check(ModelFetch.verified(resumed.appendingPathComponent(file.path),file),"ModelScope config resumed, checksum verified")
            check(ModelFetch.progress(spec.id,files:[file],root:root)==1,"Progress complete")
            try fm.removeItem(at:resumed)
            let fetched=try ModelFetch.download(spec:spec,files:[file],root:root,mirror:false,ticket:ModelDownloadTicket())
            check(ModelFetch.verified(fetched.appendingPathComponent(file.path),file),"Pinned Hugging Face config verified")
        }
        let cancelled=ModelDownloadTicket();cancelled.cancel()
        do{_ = try ModelFetch.download(spec:catalog[0],files:manifest[catalog[0].id]!,root:root,mirror:true,ticket:cancelled);fatalError("Cancelled fetch ran")}catch is CancellationError{checks+=1}
        let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/sleep");process.arguments=["30"]
        let ticket=ModelDownloadTicket(),started=Date()
        let child=Task.detached{try ticket.run(process)}
        try await Task.sleep(nanoseconds:100_000_000);ticket.cancel()
        do{try await child.value;fatalError("Cancelled child succeeded")}catch is CancellationError{checks+=1}
        check(Date().timeIntervalSince(started)<3 && !process.isRunning,"Pause actually terminates transfer")
        let multi=ModelDownloadTicket()
        let children=(0..<3).map{_ -> Process in let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/sleep");p.arguments=["30"];return p}
        let running=children.map{p in Task.detached{try multi.run(p)}}
        try await Task.sleep(nanoseconds:150_000_000);multi.cancel()
        for child in running{do{try await child.value;fatalError("Parallel child survived cancellation")}catch is CancellationError{checks+=1}}
        check(children.allSatisfy{!$0.isRunning},"Pause terminates every parallel connection")
        for _ in 0..<50{
            let racing=Process();racing.executableURL=URL(fileURLWithPath:"/usr/bin/true")
            let owner=ModelDownloadTicket(),job=Task.detached{try owner.run(racing)}
            try await Task.sleep(nanoseconds:100_000);owner.cancel()
            do{try await job.value}catch is CancellationError{}
            check(!racing.isRunning,"Cancellation racing a naturally exited child remains safe")
        }
        let progressRoot=root.appendingPathComponent("range-progress"),rangeFiles=[ModelFile(path:"model.safetensors",bytes:100,sha256:String(repeating:"0",count:64))]
        let ranges=ModelFetch.directory("fixture",root:progressRoot).appendingPathComponent("model.safetensors.ranges")
        try fm.createDirectory(at:ranges,withIntermediateDirectories:true)
        try Data(repeating:0,count:20).write(to:ranges.appendingPathComponent("0.part"))
        try Data(repeating:0,count:20).write(to:ranges.appendingPathComponent("0.partial"))
        try Data(repeating:0,count:10).write(to:ranges.appendingPathComponent("1.partial"))
        check(abs(ModelFetch.progress("fixture",files:rangeFiles,root:progressRoot)-0.3)<0.001,"Live range progress counts in-flight bytes without double counting renamed parts")
        // Offline tiny catalog fixture: exercises manager's idle/cancel boundary
        // and per-role install without changing live data or starting model/audio.
        let fixtureURL=Bundle.main.url(forResource:"ModelManifest",withExtension:"json")!,original=try Data(contentsOf:fixtureURL)
        defer{try? original.write(to:fixtureURL)}
        let payload=Data("small verified fixture model".utf8),seed=root.appendingPathComponent("seed")
        try payload.write(to:seed)
        let file=ModelFile(path:"config.json",bytes:Int64(payload.count),sha256:try ModelResources.sha256(seed))
        let small=Dictionary(uniqueKeysWithValues:catalog.map{($0.id,[file])})
        try JSONEncoder().encode(small).write(to:fixtureURL)
        let app=AppState.shared,manager=ModelDownloads.shared
        check(app.store.sessions.isEmpty && app.store.vocabulary.isEmpty,"Isolated app data")
        app.resourcesBusy=true
        let spec=catalog[0],staging=ModelFetch.directory(spec.id,root:root)
        try? fm.removeItem(at:staging);try fm.createDirectory(at:staging,withIntermediateDirectories:true)
        try payload.write(to:staging.appendingPathComponent(file.path))
        manager.start(spec)
        for _ in 0..<100{if manager.fraction==1{break};try await Task.sleep(nanoseconds:20_000_000)}
        check(manager.downloading && !ModelCatalog.installed(spec.id),"Verified download waits while busy")
        manager.pause()
        for _ in 0..<100{if !manager.downloading{break};try await Task.sleep(nanoseconds:20_000_000)}
        check(!manager.downloading && !ModelCatalog.installed(spec.id),"Cancel waiting commit preserves old state")
        app.resourcesBusy=false;manager.start(spec)
        for _ in 0..<100{if !manager.downloading{break};try await Task.sleep(nanoseconds:20_000_000)}
        check(ModelCatalog.installed(spec.id),"Cached download installs once idle")
        check(ModelCatalog.missing(cleanup:.none,translate:false).isEmpty,"ASR only supports base dictation")
        check(ModelCatalog.missing(cleanup:.light,translate:false)==["Qwen3-1.7B-4bit"],"Cleanup not silently required for base mode")
        check(!fm.fileExists(atPath:AppPaths.models.appendingPathComponent("Hy-MT2-1.8B-4bit").path),"Translation never downloaded implicitly")
        let source=root.appendingPathComponent("import"),mt=catalog.first{$0.role=="mt"}!
        try fm.createDirectory(at:source.appendingPathComponent(mt.id),withIntermediateDirectories:true)
        try payload.write(to:source.appendingPathComponent(mt.id).appendingPathComponent(file.path))
        try ModelResources.importModels(from:source,manifest:[mt.id:[file]])
        check(ModelCatalog.installed(mt.id) && ModelCatalog.installed(spec.id),"Import one model preserves other installed roles")
        try Data(repeating:0,count:payload.count).write(to:source.appendingPathComponent(mt.id).appendingPathComponent(file.path))
        do{try ModelResources.importModels(from:source,manifest:[mt.id:[file]]);fatalError("Invalid hash accepted")}catch{checks+=1}
        check(ModelFetch.verified(AppPaths.models.appendingPathComponent(mt.id).appendingPathComponent(file.path),file),"Bad import never replaces working model")
        check(app.store.sessions.isEmpty,"Model work never creates history/statistics")
        print("Model download checks passed:",checks)
    }
}
