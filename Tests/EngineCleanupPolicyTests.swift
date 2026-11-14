import Foundation

@main struct EngineCleanupPolicyTests {
    @MainActor static func main() async throws {
        try AppPaths.prepare()
        let engine=EngineClient()
        var statuses:[String]=[]
        engine.onStatus={statuses.append($0)}
        try engine.start(cleanup:.structured,cleanupProvider:.deepSeek)
        try engine.configureCleanup(.structured,provider:.deepSeek)
        try engine.configureCleanup(.structured,provider:.deepSeek)
        let first=try await engine.run(["cleanup":"structured","cleanup_provider":"deepseek","text":"合成测试"])
        let jobs=first["jobs"]as![[String:Any]]
        let warm=jobs.filter{$0["action"]as?String == "prewarm"}
        assert(warm.count==1 && warm[0]["cleanup"]as?String == "structured")
        assert(warm[0]["cleanup_provider"]as?String == "deepseek")
        assert(jobs.filter{$0["action"]as?String == "configure_cleanup"}.count==1)
        assert(!statuses.contains{$0.contains("整理模型未安装")})
        try engine.configureCleanup(.light,provider:.local)
        let second=try await engine.run(["cleanup":"light","text":"合成测试"])
        let configured=(second["jobs"]as![[String:Any]]).filter{$0["action"]as?String == "configure_cleanup"}
        assert(configured.count==2 && configured.last?["cleanup_provider"]as?String == "local")
        engine.stop()
        // Restarting must resend the same settings to the new worker.
        try engine.start(prewarm:false)
        try engine.configureCleanup(.light,provider:.local)
        let third=try await engine.run(["cleanup":"none","text":"合成测试"])
        assert((third["jobs"]as![[String:Any]]).filter{$0["action"]as?String == "configure_cleanup"}.count==1)
        engine.stop()
        print("Engine cleanup policy integration passed.")
    }
}
