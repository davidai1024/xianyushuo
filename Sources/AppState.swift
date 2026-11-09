import SwiftUI
import Combine
import ApplicationServices
import UniformTypeIdentifiers
import AVFoundation
import ServiceManagement
import CoreAudio

@MainActor final class AppState:ObservableObject {
    static let shared=AppState()
    let onboarding=FirstRunState()
    var store=LibraryStore()
    let engine=EngineClient(),recorder=Recorder(),hotkeys=HotkeyManager()
    @Published var phase="idle"
    @Published var resourcesBusy=false
    @Published var stage="随时开始"
    @Published var engineStatus="引擎未启动"
    @Published var microphoneStatus="保温已关闭"
    @Published var microphoneRoute="实际输入尚未就绪"
    @Published var correctionSuggestion:CorrectionProposal?
    private let correctionMonitor=CorrectionMonitor()
    private let correctionPrompt=CorrectionPrompt()
    private let recordingMute=RecordingMuteController()
    private var pendingMuteRelease:String?
    @Published var outputMuteStatus="录音时自动静音，结束后恢复原状态。"
    let meter=WaveformSignal()
    @Published var elapsed=0.0
    @Published var notice=""
    @Published var page="输入"
    @Published var microphones:[MicrophoneChoice]=[]
    @Published var shortcutError=""
    @Published var latest:UUID?
    @Published var permissionsVersion=0
    @Published var overlayExpanded=false
    @Published var processingStarted=Date()
    @Published var deliveryState="saved"
    var overlay:OverlayController?
    var showMain:(()->Void)?
    var showOnboarding:(()->Void)?
    var updateDockVisibility:((Bool)->Void)?
    private var outputObserver:DefaultInputObserver?
    var headphoneWarmSuppressed:Bool {store.preferences.preserveHeadphoneControls && AudioDevices.headphonesInUse(uid:store.preferences.microphoneUID,preferBuiltIn:store.preferences.preferBuiltIn)}
    private var effectiveMicWarm:Bool {MicWarmPolicy.allows(requested:store.preferences.keepMicWarm,protectControls:store.preferences.preserveHeadphoneControls,bluetooth:headphoneWarmSuppressed)}
    private var subscription:AnyCancellable?
    private var tick:Timer?
    private var started=Date()
    private var active:UUID?
    private var target:PasteTarget?
    private var pendingDelivery:Task<Void,Never>?
    private var activationGeneration=0
    private var sleeping=false
    private var beginToken=0
    private let captureStop=RecordingStopController()
    private var finishingCapture:Bool {captureStop.pending}
    private var lastAccessibility=false
    private var servicesStarted=false
    private var inputObserver:DefaultInputObserver?
    private var configurationObserver:AudioConfigurationObserver?
    private var warmToken=0
    private var streamingTasks:[Int:Task<[String:Any],Error>]=[:]
    var capturing:Bool {phase=="preparing" || phase=="recording"}
    var busy:Bool {resourcesBusy || capturing || phase=="working"}
    var latestRecord:SessionRecord? {store.sessions.first(where:{$0.id==latest}) ?? store.sessions.first}
    init(){
        recordingMute.onStatus={ [weak self] status in self?.outputMuteStatus=status }
        subscription=store.objectWillChange.sink{[weak self]in self?.objectWillChange.send()}
        hotkeys.onAction={ [weak self] id,down in Task { @MainActor in self?.hotkey(id,down:down) } }
        hotkeys.onEscape={ [weak self] in Task { @MainActor in if self?.busy==true{self?.cancel()} } }
        hotkeys.onCommit={ [weak self]in Task{@MainActor in self?.correctionMonitor.commit()}}
        hotkeys.onStandaloneInterrupted={ [weak self] in Task{@MainActor in self?.beginToken+=1;if self?.capturing==true{self?.cancel()}} }
        recorder.onReleaseFinished={ [weak self]in
            guard let self else{return}
            self.finishPendingSoundRestore()
            if !self.capturing && self.microphoneStatus=="耳机音乐控制保护中：正在释放麦克风。"{self.microphoneStatus="耳机音乐控制保护中：麦克风已释放。"}
            if !self.busy && !self.sleeping && self.store.preferences.keepMicWarm{self.applyPreferences()}
        }
        recorder.onLevels={ [weak self] values in if self?.phase=="recording"{self?.meter.update(values)} }
        recorder.onError={ [weak self] message in self?.notice=message;if self?.capturing==true || self?.finishingCapture==true{self?.finish(drainTail:false)} }
        recorder.onSegmentReady={ [weak self] segment in self?.enqueueSegment(segment) }
        engine.onProgress={ [weak self] _,message in
            guard let self,self.active != nil,self.phase=="working",!self.finishingCapture else{return}
            self.stage=OverlayLayout.processingTitle(message)
        }
        engine.onStatus={ [weak self] status in self?.engineStatus=status }
        engine.onCheckpoint={ [weak self] _,checkpoint in self?.checkpoint(checkpoint) }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.sleep()}}
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main){[weak self]_ in Task{@MainActor in self?.wake()}}
        configurationObserver=AudioConfigurationObserver{[weak self] source in
            guard let self,self.recorder.configurationIdentity==source else{return}
            self.deviceChanged()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main){[weak self]_ in
            Task{@MainActor in
                guard let self else{return}
                self.activationGeneration &+= 1
                self.refreshPermissions()
            }
        }
        refreshDevices();applyPreferences();store.expireAudio()
        if !ModelCatalog.installed("Qwen3-ASR-1.7B-8bit"){page="模型资源"}
        correctionMonitor.onProposal={ [weak self] proposal in
            guard let self,!busy else{return};correctionSuggestion=proposal;showCorrectionPrompt()
        }
        correctionMonitor.onInvalidated={ [weak self]in self?.dismissCorrection() }
        inputObserver=DefaultInputObserver{[weak self]in Task{@MainActor in
            guard let self,self.store.preferences.microphoneUID.isEmpty,!self.store.preferences.preferBuiltIn else{return}
            self.refreshDevices()
            if self.capturing || self.finishingCapture{self.notice="系统默认麦克风已切换，当前录音已结束并保留。";self.finish(drainTail:false)}else{self.recorder.shutdown();self.applyPreferences()}
        }}
        outputObserver=DefaultInputObserver(selector:kAudioHardwarePropertyDefaultOutputDevice){[weak self]in
            Task{@MainActor in
                guard let self,!self.capturing,!self.finishingCapture else{return}
                if self.busy{
                    if self.headphoneWarmSuppressed{self.recorder.shutdown();self.microphoneStatus="耳机音乐控制保护中：麦克风已释放。"}
                }else{self.applyPreferences()}
            }
        }
        if let record=store.sessions.first(where:{$0.status=="interrupted"}){latest=record.id;notice="有上次中断的任务，可在历史中恢复。"}
    }
    func startServices(){
        do{try engine.start()}catch{engineStatus=error.localizedDescription}
        if !servicesStarted {
            servicesStarted=true
            // First launch must return to the app run loop before CoreAudio starts pulling.
            DispatchQueue.main.asyncAfter(deadline:.now()+0.35){[weak self]in self?.applyPreferences()}
        }
    }
    func applyPreferences(){
        store.savePreferences();updateDockVisibility?(store.preferences.hideDockIcon);hotkeys.standaloneHold=store.preferences.holdToTalk;hotkeys.configure(store.preferences.dictation,store.preferences.translation);shortcutError=hotkeys.errors.joined(separator:"\n")
        if servicesStarted && !busy && !sleeping {
            warmToken+=1;let token=warmToken
            if effectiveMicWarm && Recorder.authorized {
                do {
                    try recorder.prepare(uid:store.preferences.microphoneUID,preferBuiltIn:store.preferences.preferBuiltIn);microphoneStatus="麦克风准备中…"
                    Task {
                        let ready=await recorder.waitForAudio()
                        guard token==warmToken,!busy else{return}
                        if ready{microphoneStatus="保温已生效，麦克风正在返回音频。";microphoneRoute=recorder.inputSummary}
                        else{recorder.shutdown();microphoneRoute=recorder.inputSummary;microphoneStatus="保温未生效：麦克风没有返回音频，请刷新或重新选择设备。"}
                    }
                }catch{microphoneRoute=recorder.inputSummary;microphoneStatus="保温未生效：\(error.localizedDescription)"}
            }
            else {recorder.shutdown();microphoneRoute=recorder.inputSummary;microphoneStatus=store.preferences.keepMicWarm && headphoneWarmSuppressed ? "耳机音乐控制保护中：空闲时释放麦克风，保温暂时停用。":"保温已关闭"}
        }
    }
    func refreshDevices(){microphones=AudioDevices.list()}
    func pauseShortcutCapture(_ paused:Bool){hotkeys.suppress=paused;if !paused{shortcutError=hotkeys.errors.joined(separator:"\n")}}
    func hotkey(_ id:UInt32,down:Bool){
        if store.preferences.holdToTalk { if down && !busy {begin(translate:id==2,fromHotkey:true)}else if !down {beginToken+=1;if capturing{finish()}} }
        else if down { if capturing{finish()}else if !busy{begin(translate:id==2,fromHotkey:true)} }
    }
    func begin(translate:Bool=false,practice:Bool=false,fromHotkey:Bool=false){
        guard !busy else{return}
        stopPendingDelivery()
        if onboarding.visible && onboarding.step != .practice{onboarding.error="请先完成当前步骤，或选择“稍后设置”。";showOnboarding?();return}
        let practicing=practice || (onboarding.visible && onboarding.step == .practice)
        let missing=ModelCatalog.missing(cleanup:store.preferences.cleanup,translate:translate)
        guard missing.isEmpty else{
            if onboarding.visible{onboarding.go(.models);onboarding.error="请先下载本次使用的模型。"}
            page="模型资源";notice="请先下载所需模型："+missing.joined(separator:"、")+"。只需基础听写时，可使用“不整理”。";showMain?();return
        }
        correctionMonitor.stop();dismissCorrection()
        // A cancelled/crashed worker is restarted while the user is speaking.
        startServices()
        beginToken+=1;let token=beginToken
        var destination=practicing ? nil:PasteTarget.capture()
        if fromHotkey,store.preferences.autoPaste,store.preferences.keepClipboard,let captured=destination,
           captured.bundleID==WeChatPasteContext.bundleID,captured.element==nil,captured.focusedOwner==nil,let pid=captured.pid {
            destination?.weChatContext=WeChatPasteContext.capture(pid:pid,activationGeneration:activationGeneration)
        }
        phase="preparing";stage="准备录音";notice="";elapsed=0;meter.reset();overlay?.show()
        Task {
            await Task.yield()
            if !Recorder.authorized {guard await Recorder.request() else{phase="error";stage="需要麦克风授权";notice="麦克风尚未授权，请在设置中允许咸鱼说录音。";page="权限";return}}
            guard phase=="preparing",token==beginToken else{return}
            await recorder.waitForRelease()
            guard phase=="preparing",token==beginToken else{return}
            finishPendingSoundRestore()
            var record=SessionRecord();record.cleanup=store.preferences.cleanup;record.translate=translate;record.words=store.activeWords
            if practicing{record.source="onboarding";onboarding.startedTrial(record.id)}
            record.audioFile=record.id.uuidString+".wav"
            record.metadata=String(data:(try? JSONSerialization.data(withJSONObject:["input_capture":destination?.audit ?? ["purpose":"onboarding_practice","external_target_captured":false]],options:[.prettyPrinted,.sortedKeys])) ?? Data(),encoding:.utf8) ?? ""
            do {
                try store.update(record)
                active=record.id;latest=record.id;target=destination;streamingTasks.removeAll()
                _ = recordingMute.begin(enabled:store.preferences.muteWhileRecording)
                try recorder.begin(url:AppPaths.audio.appendingPathComponent(record.audioFile),uid:store.preferences.microphoneUID,preferBuiltIn:store.preferences.preferBuiltIn,stream:store.preferences.streamWhileRecording)
                // Bluetooth can reset output mute before its first nonzero PCM.
                // Protect that initial profile switch while the orb is visible.
                recordingMute.captureReady()
                let ready=await recorder.waitForAudio()
                guard phase=="preparing",token==beginToken else{return}
                guard ready else{throw AppError.message("麦克风仍在返回静音，请检查耳机连接或麦克风静音状态。录音已保留。")}
                recordingMute.captureReady()
                microphoneRoute=recorder.inputSummary
                var capture=(try? JSONSerialization.jsonObject(with:Data(record.metadata.utf8)))as?[String:Any] ?? [:]
                capture["audio_input"]=recorder.inputAudit.merging(recorder.readinessAudit){_,new in new}
                record.metadata=String(data:try JSONSerialization.data(withJSONObject:capture,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8) ?? ""
                try store.update(record)
                started=Date();phase="recording";stage=translate ? "录音 · 直接出英文":"正在录音";microphoneStatus=effectiveMicWarm ? "保温已生效，麦克风正在返回音频。":"录音中"
                tick?.invalidate()
                tick=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true){[weak self]_ in Task{@MainActor in self?.recordingTick()}}
            } catch { pendingMuteRelease=recordingMute.prepareForDeviceRelease();recorder.shutdown();endRecordingSound();record.status="failed";record.error=error.localizedDescription;try? store.update(record);notice=error.localizedDescription;active=nil;phase="error";stage="录音未开始";overlay?.show() }
        }
    }
    private func endRecordingSound(){
        if recorder.releasePending{pendingMuteRelease=recordingMute.pauseForDeviceRelease()}
        else{let owner=pendingMuteRelease;pendingMuteRelease=nil;recordingMute.end(owner:owner)}
        if !effectiveMicWarm{
            microphoneStatus=headphoneWarmSuppressed ? (recorder.releasePending ? "耳机音乐控制保护中：正在释放麦克风。":"耳机音乐控制保护中：麦克风已释放。") : "保温已关闭"
        }
    }
    private func finishPendingSoundRestore(){
        guard let owner=pendingMuteRelease else{return}
        pendingMuteRelease=nil;recordingMute.end(owner:owner)
    }
    private func recordingTick(){
        guard phase=="recording" else{return};elapsed=Date().timeIntervalSince(started)
        if elapsed>=600 {finish(drainTail:false);return}
        if elapsed>4 && Date().timeIntervalSince(recorder.lastBufferTime)>3 {notice="麦克风没有返回音频，已停止并保留任务。";finish(drainTail:false)}
    }
    func finish(drainTail:Bool=true){
        guard capturing || finishingCapture else{return}
        let alreadyFinishing=finishingCapture
        beginToken+=1
        guard let id=active else{endRecordingSound();phase="result";stage="已取消";notice="录音准备已取消。";overlay?.show();return}
        tick?.invalidate();tick=nil
        let stop=ProcessInfo.processInfo.systemUptime,framesBeforeSeconds=recorder.duration
        let tail=drainTail && !sleeping && !alreadyFinishing && framesBeforeSeconds<599.5 ? recorder.stopTailSeconds:0
        phase="working";stage="正在收尾";processingStarted=Date()
        captureStop.request(after:tail){[weak self]in
            self?.completeCapture(id:id,stop:stop,before:framesBeforeSeconds,requestedTail:tail)
        }
    }
    private func completeCapture(id:UUID,stop:Double,before:Double,requestedTail:Double){
        guard active==id,phase=="working",var record=store.sessions.first(where:{$0.id==id})else{return}
        let completionStarted=ProcessInfo.processInfo.systemUptime
        let suppress=headphoneWarmSuppressed
        let keepWarm=MicWarmPolicy.allows(requested:store.preferences.keepMicWarm,protectControls:store.preferences.preserveHeadphoneControls,bluetooth:suppress) && !sleeping
        let policySeconds=ProcessInfo.processInfo.systemUptime-completionStarted
        pendingMuteRelease=recordingMute.prepareForDeviceRelease()
        let writerStarted=ProcessInfo.processInfo.systemUptime
        record.duration=recorder.finish(keepWarm:keepWarm,releaseAsynchronously:true)
        let writerSeconds=ProcessInfo.processInfo.systemUptime-writerStarted
        let restoreStarted=ProcessInfo.processInfo.systemUptime
        endRecordingSound()
        let restoreSeconds=ProcessInfo.processInfo.systemUptime-restoreStarted
        if suppress{microphoneStatus=recorder.releasePending ? "耳机音乐控制保护中：正在释放麦克风。":"耳机音乐控制保护中：麦克风已释放。"}
        var capture=(try? JSONSerialization.jsonObject(with:Data(record.metadata.utf8)))as?[String:Any] ?? [:]
        capture["live_capture"]=recorder.streamingAudit
        capture["recording_stop"]=["requested_tail_seconds":requestedTail,"actual_tail_seconds":ProcessInfo.processInfo.systemUptime-stop,"duration_before_stop":before,"extra_pcm_seconds":max(0,record.duration-before),"completion_queue_delay_seconds":max(0,completionStarted-stop-requestedTail),"device_policy_seconds":policySeconds,"writer_finalize_seconds":writerSeconds,"output_restore_request_seconds":restoreSeconds,"output_restore_deferred":recorder.releasePending,"hardware_release_deferred":recorder.releasePending]
        record.metadata=String(data:(try? JSONSerialization.data(withJSONObject:capture,options:[.prettyPrinted,.sortedKeys])) ?? Data(),encoding:.utf8) ?? ""
        for segment in recorder.completedSegments{enqueueSegment(segment)}
        record.status="processing"
        do{try store.update(record)}catch{phase="error";notice="无法保存录音状态，已停止处理：\(error.localizedDescription)";return}
        if record.duration<0.12 {record.status="failed";record.error="录音太短或麦克风未返回音频，文件已保留。";try? store.update(record);phase="error";stage="录音未完成";active=nil;return}
        phase="working";stage="正在识别";run(record,autoDeliver:record.source != "onboarding")
    }
    private func enqueueSegment(_ segment:CapturedSegment){
        guard capturing || phase=="working",let id=active,id.uuidString==segment.owner,streamingTasks[segment.index]==nil,
              let record=store.sessions.first(where:{$0.id==id})else{return}
        var payload=segment.payload;payload["action"]="asr_chunk";payload["words"]=record.words
        payload["cleanup"]=record.cleanup.rawValue
        streamingTasks[segment.index]=Task{try await engine.run(payload)}
    }
    private func checkpoint(_ value:[String:Any]){
        guard let id=active,var record=store.sessions.first(where:{$0.id==id})else{return}
        if let raw=value["raw"]as?String {record.raw=raw}
        if let cleaned=value["cleaned"]as?String {record.cleaned=cleaned}
        if let seconds=value["duration"]as?Double,seconds>0{record.duration=seconds}
        do{try store.update(record)}catch{engine.stop(reason:"阶段结果保存失败，原录音保留。");notice=error.localizedDescription}
    }
    private func run(_ original:SessionRecord,autoDeliver:Bool){
        let id=original.id
        let chunks=autoDeliver ? streamingTasks.sorted{$0.key<$1.key}.map(\.value):[]
        Task {
            defer{if autoDeliver{StreamingCapture.remove(id.uuidString)}}
            var payload:[String:Any]=["words":original.words,"cleanup":original.cleanup.rawValue,"translate":original.translate]
            if autoDeliver{payload["recording_id"]=id.uuidString}
            if !original.audioFile.isEmpty {payload["audio"]=AppPaths.audio.appendingPathComponent(original.audioFile).path}else{payload["text"]=original.raw}
            do{
                let waiting=Date();var tickets:[String]=[]
                for chunk in chunks{
                    if let value=try? await chunk.value,let ticket=value["ticket"]as?String{tickets.append(ticket)}
                }
                guard active==id else{return}
                if !chunks.isEmpty,tickets.count==chunks.count{payload["streaming_tickets"]=tickets;payload["recording_id"]=id.uuidString}
                let backgroundWait=Date().timeIntervalSince(waiting)
                let result=try await engine.run(payload)
                guard active==id,var record=store.sessions.first(where:{$0.id==id})else{return}
                record.raw=result["raw"]as?String ?? record.raw;record.cleaned=result["cleaned"]as?String ?? record.raw
                record.translated=result["translated"]as?String ?? "";record.output=result["output"]as?String ?? record.cleaned
                if let duration=result["duration"]as?Double,duration>0{record.duration=duration}
                var metadata=result["metadata"]as?[String:Any] ?? [:]
                if let prior=(try? JSONSerialization.jsonObject(with:Data(original.metadata.utf8)))as?[String:Any]{for key in ["input_capture","audio_input","live_capture","recording_stop"]{if let value=prior[key]{metadata[key]=value}}}
                metadata["streaming_wait_after_stop_seconds"]=backgroundWait
                metadata["stop_to_processed_seconds"]=Date().timeIntervalSince(processingStarted)
                record.processingSeconds=Date().timeIntervalSince(processingStarted)
                streamingTasks.removeAll()
                record.metadata=String(data:try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8) ?? ""
                record.finished=Date();record.status="completed";record.error=""
                // A persistence failure must stop delivery; never paste an unsaved result.
                let persistenceStart=ProcessInfo.processInfo.systemUptime
                try store.update(record)
                metadata["result_persistence_seconds"]=ProcessInfo.processInfo.systemUptime-persistenceStart
                stage="正在完成"
                let deliveryStart=ProcessInfo.processInfo.systemUptime
                let receipt:DeliveryReceipt
                if autoDeliver{receipt=await Delivery.deliver(record.output,target:target,preferences:store.preferences,activationGeneration:activationGeneration,stillCurrent:{self.active==id && self.phase=="working"})}
                else{receipt=DeliveryReceipt(state:"saved",message:"结果已保存，可复制或查看原文。",audit:["method":"manual_result"])}
                guard active==id else{return}
                metadata["delivery"]=receipt.audit
                metadata["delivery_wall_seconds"]=ProcessInfo.processInfo.systemUptime-deliveryStart
                metadata["stop_to_delivery_seconds"]=Date().timeIntervalSince(processingStarted)
                if receipt.state=="verified"{metadata["overlay_verified_hold_seconds"]=OverlayLayout.verifiedHoldSeconds;RuntimeDiagnostics.event("delivery_verified")}
                record.metadata=String(data:try JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8) ?? ""
                record.delivery=receipt.message
                if receipt.state=="empty"{record.status="failed";record.error=receipt.message}
                try store.update(record);deliveryState=receipt.state;phase=receipt.state=="empty" ? "error":"result"
                stage=receipt.state=="verified" ? "已填入":receipt.state=="clipboard" ? "可粘贴":receipt.state=="unverified" ? "待确认":receipt.state=="empty" ? "未识别到语音":"已保存"
                notice=record.delivery;active=nil;latest=id;overlay?.show()
                if autoDeliver{
                    startCorrectionTracking(id:id,text:record.output,receipt:receipt)
                    if receipt.audit["clipboard_unchanged"]as?Bool == true,DeliveryTargetPolicy.mayWait(reason:receipt.audit["reason"]as?String ?? "",state:receipt.state,autoPaste:store.preferences.autoPaste){awaitInput(id:id)}
                }
            }catch{
                guard active==id,var record=store.sessions.first(where:{$0.id==id})else{return}
                record.status="failed";record.error=error.localizedDescription;try? store.update(record)
                phase="error";stage="处理未完成";notice="\(error.localizedDescription)\n录音和已识别文字已保留。";active=nil;overlay?.show()
            }
        }
    }
    private func startCorrectionTracking(id:UUID,text:String,receipt:DeliveryReceipt){
        guard ["verified","unverified"].contains(receipt.state),let destination=receipt.resolvedTarget,destination.element != nil else{return}
        target=destination
        correctionMonitor.onStatus={[weak self] status in self?.recordCorrectionStatus(id,status)}
        correctionMonitor.start(target:destination,inserted:text,observedBaseline:receipt.observedInsertionBaseline,existing:{[weak self]in self?.store.vocabulary.map(\.word) ?? []})
    }
    private func stopPendingDelivery(){pendingDelivery?.cancel();pendingDelivery=nil}
    private func awaitInput(id:UUID){
        stopPendingDelivery()
        let start=ProcessInfo.processInfo.systemUptime
        let version=NSPasteboard.general.changeCount
        pendingDelivery=Task{[weak self]in
            var lease=PendingDeliveryLease(id:id,deadline:start+DeliveryTargetPolicy.waitSeconds,clipboardVersion:version)
            while !Task.isCancelled,ProcessInfo.processInfo.systemUptime<lease.deadline{
                try? await Task.sleep(nanoseconds:120_000_000)
                guard !Task.isCancelled,let self,!self.busy,!self.sleeping,self.latest==id,self.phase=="result",self.store.preferences.autoPaste,
                      NSPasteboard.general.changeCount==version else{return}
                let destination=PasteTarget.capture()
                let available=destination.element != nil && destination.pid != nil && destination.pid != getpid()
                guard lease.claim(id:id,now:ProcessInfo.processInfo.systemUptime,clipboardVersion:NSPasteboard.general.changeCount,inputAvailable:available)else{continue}
                guard var record=self.store.sessions.first(where:{$0.id==id}),record.status=="completed",!record.output.isEmpty else{return}
                // The user may have pasted our clipboard before the next poll.
                // Existing text is not delivery proof; simply avoid a duplicate write.
                if DeliveryEvidence.alreadyAtCursor(value:destination.text,range:destination.selection,inserted:record.output){return}
                // Output is already durable. Claim once before any possible write.
                var metadata=(try? JSONSerialization.jsonObject(with:Data(record.metadata.utf8)))as?[String:Any] ?? [:]
                let receipt=await Delivery.deliver(record.output,target:destination,preferences:self.store.preferences,stillCurrent:{!Task.isCancelled && !self.busy && !self.sleeping && self.latest==id && self.phase=="result" && self.store.sessions.contains{$0.id==id && $0.status=="completed"}})
                guard !Task.isCancelled,self.latest==id,!self.busy,self.store.sessions.contains(where:{$0.id==id && $0.status=="completed"}) else{return}
                metadata["initial_delivery"]=metadata["delivery"]
                metadata["delivery"]=receipt.audit
                metadata["late_focus_wait_seconds"]=ProcessInfo.processInfo.systemUptime-start
                metadata["late_delivery_wall_seconds"]=receipt.audit["total_seconds"]
                if receipt.state=="verified"{metadata["overlay_verified_hold_seconds"]=OverlayLayout.verifiedHoldSeconds;RuntimeDiagnostics.event("delivery_verified")}
                record.metadata=String(data:(try? JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys])) ?? Data(),encoding:.utf8) ?? ""
                record.delivery=receipt.message
                do{try self.store.update(record)}catch{self.notice="结果已保留，但无法保存填入状态：\(error.localizedDescription)";return}
                self.deliveryState=receipt.state;self.stage=receipt.state=="verified" ? "已填入":receipt.state=="unverified" ? "待确认":"可粘贴"
                self.notice=receipt.message;self.overlay?.show()
                self.startCorrectionTracking(id:id,text:record.output,receipt:receipt)
                return
            }
        }
    }
    func retry(_ original:SessionRecord){
        guard !busy else{return};var record=original
        stopPendingDelivery()
        if !record.output.isEmpty {record.versions.append(record.output)}
        record.words=store.activeWords;record.cleanup=store.preferences.cleanup;record.status="processing";record.error=""
        do{try store.update(record)}catch{notice=error.localizedDescription;return}
        active=record.id;latest=record.id;target=nil;phase="working";processingStarted=Date();stage="正在重新处理";overlay?.show();run(record,autoDeliver:false)
    }
    func testText(_ text:String,translate:Bool){
        guard !busy,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        stopPendingDelivery()
        var r=SessionRecord();r.source="text-test";r.status="processing";r.raw=text;r.cleanup=store.preferences.cleanup;r.translate=translate;r.words=store.activeWords
        do{try store.update(r)}catch{notice=error.localizedDescription;return}
        active=r.id;latest=r.id;target=nil;phase="working";processingStarted=Date();stage="正在测试文本";run(r,autoDeliver:false)
    }
    func importAudio(){
        guard !busy else{return}
        stopPendingDelivery()
        let panel=NSOpenPanel();panel.allowedContentTypes=[.wav,.aiff,.audio];panel.allowsMultipleSelection=false
        guard panel.runModal()       == .OK,let url=panel.url else{return}
        var r=SessionRecord();r.source="audio-import";r.status="processing";r.cleanup=store.preferences.cleanup;r.words=store.activeWords
        r.audioFile=r.id.uuidString+".wav"
        do{try AudioFiles.convert(url,to:AppPaths.audio.appendingPathComponent(r.audioFile));try store.update(r)}catch{notice="无法读取该音频格式：\(error.localizedDescription)";return}
        active=r.id;latest=r.id;target=nil;phase="working";processingStarted=Date();stage="正在识别文件";run(r,autoDeliver:false)
    }
    func cancel(){
        stopPendingDelivery()
        if resourcesBusy{notice="模型文件操作正在进行，请等待校验和保存完成。";return}
        guard busy else{endRecordingSound();return};beginToken+=1;tick?.invalidate();tick=nil
        var recordedDuration:Double?
        if capturing || finishingCapture{pendingMuteRelease=recordingMute.prepareForDeviceRelease();recordedDuration = recorder.finish(keepWarm:effectiveMicWarm)}
        captureStop.cancel()
        if !capturing || !streamingTasks.isEmpty{engine.stop()}
        endRecordingSound()
        if let id=active,var r=store.sessions.first(where:{$0.id==id}){if let recordedDuration{r.duration=recordedDuration};r.status="cancelled";r.error="已取消，录音和已完成的文字保留，可在历史中恢复。";try? store.update(r)}
        if let id=active{StreamingCapture.remove(id.uuidString)};streamingTasks.removeAll()
        active=nil;phase="result";stage="已取消";notice="已保留到历史，可稍后恢复。";overlay?.show()
    }
    func sleep(){stopPendingDelivery();activationGeneration &+= 1;sleeping=true;if capturing || finishingCapture{finish(drainTail:false)};recorder.shutdown();endRecordingSound()}
    func wake(){sleeping=false;refreshDevices();applyPreferences();permissionsVersion+=1}
    func deviceChanged(){guard recorder.shouldHandleConfigurationChange else{return};refreshDevices();if capturing || finishingCapture{notice="录音设备发生变化，当前录音已保留。";finish(drainTail:false)}else{recorder.shutdown();applyPreferences()}}
    func startOnboarding(){
        guard !busy else{notice="请先结束或取消当前任务，再打开引导。";return}
        stopPendingDelivery()
        onboarding.present(replay:true);showOnboarding?()
    }
    func refreshPermissions(){permissionsVersion+=1;let granted=AXIsProcessTrusted();if granted != lastAccessibility{lastAccessibility=granted;hotkeys.refreshMonitors()}}
    func setLogin(_ enabled:Bool){
        do{if enabled{try SMAppService.mainApp.register()}else{try SMAppService.mainApp.unregister()};store.preferences.launchAtLogin=enabled;store.savePreferences()}catch{notice="登录启动设置未生效：\(error.localizedDescription)"}
    }
    func openPrivacy(_ pane:String){if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?\(pane)"){NSWorkspace.shared.open(url)}}
    func requestAccessibility(){let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true]as CFDictionary;_ = AXIsProcessTrustedWithOptions(options);openPrivacy("Privacy_Accessibility");refreshPermissions()}
    func showCorrectionPrompt(error:String=""){
        guard let proposal=correctionSuggestion,CorrectionLearning.enabled else{return}
        correctionPrompt.show(proposal,error:error,accept:{[weak self]in self?.acceptCorrection()},dismiss:{[weak self]in self?.ignoreCorrection()})
    }
    private func recordCorrectionStatus(_ id:UUID,_ status:String){
        if ["foreground_changed","input_unreadable_or_changed","outside_insertion_changed","timeout"].contains(status){correctionPrompt.close()}
        guard var record=store.sessions.first(where:{$0.id==id})else{return}
        var metadata=(try? JSONSerialization.jsonObject(with:Data(record.metadata.utf8)))as?[String:Any] ?? [:]
        metadata["correction_learning"]=["status":status,"version":1]
        guard let bytes=try? JSONSerialization.data(withJSONObject:metadata,options:[.prettyPrinted,.sortedKeys]),let text=String(data:bytes,encoding:.utf8)else{return}
        record.metadata=text;try? store.update(record)
    }
    func acceptCorrection(){
        guard !busy,let proposal=correctionSuggestion else{return}
        guard correctionMonitor.canAccept(proposal.word)else{dismissCorrection();notice="文字还在修改，稍等片刻会更新词表建议。";return}
        do{
            var values=store.vocabulary
            if let i=values.firstIndex(where:{VocabularyRules.key($0.word)==VocabularyRules.key(proposal.word)}){values[i].enabled=true}
            else{values.append(VocabularyEntry(word:proposal.word))}
            try store.saveVocabulary(values);correctionMonitor.accepted();notice="已加入词表：\(proposal.word)，下次录音生效。";dismissCorrection()
        }catch{notice=error.localizedDescription;showCorrectionPrompt(error:error.localizedDescription)}
    }
    func ignoreCorrection(){if let suggestion=correctionSuggestion{correctionMonitor.ignore(suggestion.word)};dismissCorrection()}
    func dismissCorrection(){correctionPrompt.close();correctionSuggestion=nil}
    func stopCorrectionLearning(){correctionMonitor.stop();dismissCorrection()}
    func shutdown(){stopPendingDelivery();ModelDownloads.shared.pause();stopCorrectionLearning();tick?.invalidate();if busy{cancel()};recorder.shutdown();endRecordingSound();engine.stop()}
}
