import SwiftUI
import AppKit

@main struct OnboardingTests {
    @MainActor static func main()async throws{
        let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("DianyuSetupTests-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);defer{try? fm.removeItem(at:root)}
        var checks=0
        func check(_ condition:Bool,_ label:String){precondition(condition,label);checks+=1}
        let fresh=FirstRunState(root:root)
        check(fresh.shouldPresentAutomatically && !fresh.visible,"Fresh installation opens only when controller presents")
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let preferences=Data("{\"cleanup\":\"light\"}".utf8);try preferences.write(to:root.appendingPathComponent("preferences.json"))
        check(fresh.shouldPresentAutomatically,"Store creating preferences cannot change first-run decision")
        fresh.present();fresh.go(.permissions)
        let resumed=FirstRunState(root:root)
        check(resumed.step == .permissions && resumed.shouldPresentAutomatically,"Interrupted introduction resumes despite now-existing preferences")
        resumed.present();resumed.go(.models);resumed.deferSetup()
        let deferred=FirstRunState(root:root)
        check(!deferred.shouldPresentAutomatically && deferred.step == .models,"Defer retains exact step and does not reopen on restart")
        deferred.present();check(deferred.step == .models,"Ordinary presentation resumes exact step")
        deferred.deferSetup();deferred.present(replay:true)
        check(deferred.step == .welcome && deferred.visible,"Explicit replay starts at welcome")
        deferred.shortcutRecording=true;deferred.go(.ready)
        check(deferred.step == .welcome,"Navigation cannot discard active shortcut capture")
        deferred.shortcutRecording=false;deferred.go(.ready);deferred.finish()
        check(FirstRunState(root:root).progress.finished && !FirstRunState(root:root).shouldPresentAutomatically,"Completion persists independently of permissions")
        check(try Data(contentsOf:root.appendingPathComponent("preferences.json"))==preferences,"Wizard progress never rewrites user preferences")
        let legacyRoot=root.appendingPathComponent("legacy");try fm.createDirectory(at:legacyRoot,withIntermediateDirectories:true)
        try preferences.write(to:legacyRoot.appendingPathComponent("preferences.json"))
        let legacy=FirstRunState(root:legacyRoot)
        check(legacy.legacy && !legacy.shouldPresentAutomatically,"Existing users are never forced into onboarding on upgrade")
        let brokenRoot=root.appendingPathComponent("broken");try fm.createDirectory(at:brokenRoot,withIntermediateDirectories:true)
        let broken=Data("malformed onboarding".utf8);try broken.write(to:brokenRoot.appendingPathComponent("onboarding.json"))
        let bad=FirstRunState(root:brokenRoot);bad.present(replay:true);bad.go(.ready);bad.finish()
        check(try Data(contentsOf:brokenRoot.appendingPathComponent("onboarding.json"))==broken && !bad.error.isEmpty,"Malformed progress is retained and error stays visible")
        for mic in [false,true]{for ax in [false,true]{for model in [false,true]{for keys in [false,true]{for busy in [false,true]{
            for step in SetupStep.allCases{
                let expected = !busy && (step == .permissions ? mic && ax:step == .models ? model:step == .shortcuts ? keys:true)
                check(FirstRunState.canContinue(step,microphone:mic,accessibility:ax,models:model,shortcuts:keys,busy:busy)==expected,"Truthful continuation guard")
            }
            let expected:SetupStep? = !mic || !ax ? .permissions:!model ? .models:!keys ? .shortcuts:nil
            check(FirstRunState.firstMissing(microphone:mic,accessibility:ax,models:model,shortcuts:keys)==expected,"Final summary routes to first actual missing capability")
        }}}}}
        var trial=SessionRecord();trial.source="onboarding";trial.status="completed";trial.finished=Date();trial.output="引导测试";check(!trial.counted,"Actual onboarding capture excluded from statistics")
        trial.source="microphone";check(trial.counted,"Ordinary microphone captures retain previous statistics policy")
        let app=AppState.shared
        check(!app.onboarding.visible,"App creation alone never presents a window")
        let original=app.store.preferences;app.startOnboarding();check(app.onboarding.visible && app.onboarding.step == .welcome,"Replay entry active")
        check(app.store.preferences==original,"Replay preserves saved shortcut and preferences")
        app.onboarding.go(.models);app.begin();check(!app.capturing && app.onboarding.step == .models,"Global shortcut cannot begin recording during setup steps")
        app.onboarding.go(.practice);app.begin(practice:true);check(!app.capturing && app.onboarding.step == .models,"Missing model routes trial to models without phantom recording")
        app.onboarding.deferSetup()
        print("Onboarding state/lifecycle checks passed:",checks)
    }
}

@MainActor final class SetupMetricStore {var frames:[SetupRegion:CGRect]=[:]}
@main struct OnboardingLayoutTests {
    @MainActor static func main()async throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("DianyuSetupLayout-"+UUID().uuidString)
        setenv("DIANYU_DATA_ROOT",root.path,1);defer{try? FileManager.default.removeItem(at:root)}
        _ = NSApplication.shared
        let app=AppState.shared;app.onboarding.present(replay:true)
        var checks=0
        func check(_ condition:Bool,_ message:String){precondition(condition,message);checks+=1}
        for appearance in [NSAppearance.Name.darkAqua,.aqua]{for size in [NSSize(width:900,height:600),NSSize(width:980,height:660),NSSize(width:1100,height:800)]{for step in SetupStep.allCases{
            app.onboarding.go(step)
            let metrics=SetupMetricStore()
            let view=SetupView(app:app,state:app.onboarding,leave:{}).onPreferenceChange(SetupFrames.self){metrics.frames=$0}
            let host=NSHostingView(rootView:view);host.sizingOptions=[];host.frame=NSRect(origin:.zero,size:size);host.appearance=NSAppearance(named:appearance)
            let window=NSWindow(contentRect:host.frame,styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.contentView=host
            host.layoutSubtreeIfNeeded();try await Task.sleep(nanoseconds:100_000_000);host.layoutSubtreeIfNeeded()
            guard let intro=metrics.frames[.introduction],let viewport=metrics.frames[.viewport],let content=metrics.frames[.content],let footer=metrics.frames[.footer]else{fatalError("Missing layout regions: \(step)")}
            let label="\(step) \(size) \(appearance)"
            check(intro.maxX<viewport.minX,"Columns never overlap "+label)
            check(footer.minY>=viewport.maxY,"Footer never covers scrollable controls "+label)
            check(intro.minY>=0 && intro.maxY<=size.height,"Introduction visible "+label)
            check(footer.maxY<=size.height && footer.width<=size.width,"Navigation visible "+label)
            check(abs(intro.midY-viewport.midY)<1,"Introduction centered to right viewport "+label)
            if content.height<=viewport.height-16+1{check(abs(content.midY-viewport.midY)<1,"Short content centered "+label)}
            else{check(content.minY>=viewport.minY-1 && content.minY<=viewport.minY+9,"Long content scrolls from top "+label)}
            check(content.width<=viewport.width+1,"No horizontal content clipping "+label)
            window.close()
        }}}
        check(!ModelDownloads.shared.downloading,"Rendering never starts a download")
        check(app.store.sessions.isEmpty,"Rendering never records or creates statistics")
        print("Onboarding layout checks passed:",checks)
    }
}
