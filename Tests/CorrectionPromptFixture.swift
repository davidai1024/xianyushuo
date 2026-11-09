import Foundation
import AppKit

/// UI-only fixture; independent bundle/data identity, no recording or global keys.
@main struct CorrectionPromptFixture {
    @MainActor static func main()throws{
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuCorrectionPromptFixture")
        setenv("DIANYU_DATA_ROOT",root.path,1)
        let store=LibraryStore(),prompt=CorrectionPrompt()
        let proposal=CorrectionProposal(removed:"desgin.fixture",word:"design.fixture")
        prompt.show(proposal,accept:{
            do{if !store.activeWords.contains(proposal.word){try store.saveVocabulary(store.vocabulary+[VocabularyEntry(word:proposal.word)])};try Data("confirmed".utf8).write(to:root.appendingPathComponent("ui-result.txt"));prompt.close();app.terminate(nil)}catch{fatalError("Fixture failed")}
        },dismiss:{try? Data("ignored".utf8).write(to:root.appendingPathComponent("ui-result.txt"));prompt.close();app.terminate(nil)})
        app.run()
    }
}
