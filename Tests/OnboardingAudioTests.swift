import Foundation
import AppKit
@main struct OnboardingAudioTests {
    @MainActor static func main()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuSetupAudio-"+UUID().uuidString),fm=FileManager.default
        setenv("DIANYU_DATA_ROOT",root.path,1);try AppPaths.prepare();defer{try? fm.removeItem(at:root)}
        let source=URL(fileURLWithPath:CommandLine.arguments[3])
        for name in try fm.contentsOfDirectory(atPath:source.path)where ["Qwen3-ASR-1.7B-8bit","Qwen3-1.7B-4bit","Hy-MT2-1.8B-4bit"].contains(name){try fm.createSymbolicLink(at:AppPaths.models.appendingPathComponent(name),withDestinationURL:source.appendingPathComponent(name))}
        let words=try JSONDecoder().decode([VocabularyEntry].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
        _=NSApplication.shared;let app=AppState.shared;try app.store.saveVocabulary(words)
        let id=try app.testRunSetupAudio(URL(fileURLWithPath:CommandLine.arguments[1]))
        for _ in 0..<3000{if !app.busy{break};try await Task.sleep(nanoseconds:40_000_000)}
        guard let result=app.store.sessions.first(where:{$0.id==id})else{fatalError("Missing saved recording")}
        precondition(result.status=="completed" && !result.output.isEmpty,"Trial completes through actual bundled inference")
        precondition(!result.counted && result.source=="onboarding","Trial excluded from statistics")
        precondition(setupExternalDeliveryCalls==0,"Trial never invokes cross-application delivery")
        precondition(app.deliveryState=="saved","Trial retains recoverable result")
        precondition(result.words==app.store.activeWords,"Full vocabulary frozen with recording")
        let meta=try JSONSerialization.jsonObject(with:Data(result.metadata.utf8))as![String:Any]
        precondition(meta["asr_dictionary_count"]as?Int==app.store.activeWords.count,"Actual ASR receives full vocabulary")
        precondition(meta["cleanup_dictionary_count"]as?Int==app.store.activeWords.count,"Actual cleanup receives full vocabulary")
        precondition(fm.fileExists(atPath:AppPaths.audio.appendingPathComponent(result.audioFile).path),"Original trial audio retained")
        app.shutdown()
        print("Onboarding actual audio pipeline checks passed: 8; full vocabulary:",app.store.activeWords.count)
    }
}
