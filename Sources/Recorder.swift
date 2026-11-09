import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

struct MicrophoneChoice: Identifiable {
    var id:String;var name:String;var device:AudioDeviceID;var builtIn:Bool
}
final class DefaultInputObserver {
    private var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    private var listener:AudioObjectPropertyListenerBlock?
    init(selector:AudioObjectPropertySelector=kAudioHardwarePropertyDefaultInputDevice,changed:@escaping()->Void){
        address.mSelector=selector
        let callback:AudioObjectPropertyListenerBlock={_,_ in changed()}
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,.main,callback)==noErr{listener=callback}
    }
    deinit{if let listener{AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,.main,listener)}}
}
enum AudioDevices {
    static func string(_ device:AudioObjectID,_ selector:AudioObjectPropertySelector)->String {
        var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var value:CFString="" as CFString,size=UInt32(MemoryLayout<CFString>.size)
        return AudioObjectGetPropertyData(device,&address,0,nil,&size,&value)==noErr ? value as String:""
    }
    static func routeMatches(_ device:AudioDeviceID?,chosen:MicrophoneChoice,choices:[MicrophoneChoice])->Bool{
        guard let device else{return false};if device==chosen.device{return true}
        // AVAudioEngine can use a private aggregate to join different default
        // input/output devices. Resolve its real input instead of overwriting it.
        var address=AudioObjectPropertyAddress(mSelector:kAudioAggregateDevicePropertyActiveSubDeviceList,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size:UInt32=0
        guard AudioObjectGetPropertyDataSize(device,&address,0,nil,&size)==noErr,size>0 else{return false}
        var devices=[AudioObjectID](repeating:0,count:Int(size)/MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&devices)==noErr else{return false}
        let active=Set(devices.map{string($0,kAudioDevicePropertyDeviceUID)})
        var composition:CFDictionary=[: ]as CFDictionary
        address.mSelector=kAudioAggregateDevicePropertyComposition;size=UInt32(MemoryLayout<CFDictionary>.size)
        guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&composition)==noErr,
              let parts=(composition as NSDictionary)[kAudioAggregateDeviceSubDeviceListKey]as?[[String:Any]]else{return false}
        let included=Set(parts.compactMap{part->String? in
            guard let uid=part[kAudioSubDeviceUIDKey]as?String,active.contains(uid),(part[kAudioSubDeviceInputChannelsKey]as?NSNumber)?.intValue != 0 else{return nil};return uid
        })
        let inputs=Set(choices.filter{included.contains($0.id)}.map(\.id))
        return inputs==[chosen.id]
    }
    static func isBluetooth(_ device:AudioDeviceID?)->Bool {
        guard let device else{return false}
        var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var transport:UInt32=0,size=UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device,&address,0,nil,&size,&transport)==noErr else{return false}
        return transport==kAudioDeviceTransportTypeBluetooth || transport==kAudioDeviceTransportTypeBluetoothLE
    }
    static func defaultOutput()->AudioDeviceID? {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var device=AudioDeviceID(0),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device)==noErr && device != 0 ? device:nil
    }
    static func headphonesInUse(uid:String,preferBuiltIn:Bool)->Bool {
        let chosen=resolve(uid:uid,preferBuiltIn:preferBuiltIn,choices:list(),defaultDevice:defaultInput())
        return isBluetooth(chosen?.device) || isBluetooth(defaultOutput())
    }
    static func defaultInput()->AudioDeviceID? {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var device=AudioDeviceID(0),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device)==noErr && device != 0 ? device:nil
    }
    static func resolve(uid:String,preferBuiltIn:Bool,choices:[MicrophoneChoice],defaultDevice:AudioDeviceID?)->MicrophoneChoice? {
        if !uid.isEmpty{return choices.first{$0.id==uid}}
        if preferBuiltIn,let builtIn=choices.first(where:{$0.builtIn}){return builtIn}
        return choices.first{$0.device==defaultDevice}
    }
    static func list()->[MicrophoneChoice] {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var size:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size)==noErr else{return []}
        var devices=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&devices)==noErr else{return []}
        return devices.compactMap { device in
            var hiddenAddress=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyIsHidden,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var hidden:UInt32=0,hiddenSize=UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device,&hiddenAddress,0,nil,&hiddenSize,&hidden)==noErr,hidden != 0{return nil}
            var input=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreams,mScope:kAudioDevicePropertyScopeInput,mElement:kAudioObjectPropertyElementMain)
            var bytes:UInt32=0
            guard AudioObjectGetPropertyDataSize(device,&input,0,nil,&bytes)==noErr,bytes>0 else{return nil}
            func string(_ selector:AudioObjectPropertySelector)->String {
                var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
                var value:CFString="" as CFString;var length=UInt32(MemoryLayout<CFString>.size)
                guard AudioObjectGetPropertyData(device,&address,0,nil,&length,&value)==noErr else{return ""}
                return value as String
            }
            var transport:UInt32=0;var length=UInt32(MemoryLayout<UInt32>.size)
            var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            AudioObjectGetPropertyData(device,&address,0,nil,&length,&transport)
            return MicrophoneChoice(id:string(kAudioDevicePropertyDeviceUID),name:string(kAudioObjectPropertyName),device:device,builtIn:transport==kAudioDeviceTransportTypeBuiltIn)
        }
    }
}
enum MicWarmPolicy {
    static func allows(requested:Bool,protectControls:Bool,bluetooth:Bool)->Bool{requested && !(protectControls && bluetooth)}
}
final class Recorder {
    private var engine:AVAudioEngine?
    private var configurationObserver:AudioConfigurationObserver?
    private var file:AVAudioFile?
    private var streaming:StreamingCapture?
    private(set) var completedSegments:[CapturedSegment]=[]
    private(set) var streamingAudit:[String:Any]=[:]
    var onReleaseFinished:(()->Void)?
    var onSegmentReady:((CapturedSegment)->Void)?
    var onConfigurationChange:(()->Void)?
    private let lock=NSLock()
    private var frames:AVAudioFramePosition=0
    private var rate=48000.0
    private var lastMeter=Date.distantPast
    private var tapInstalled=false
    private var currentUID=""
    private(set) var inputAudit:[String:Any]=[:]
    var inputSummary:String {
        guard let name=inputAudit["actual_name"]as?String,let rate=inputAudit["sample_rate"]as?Double,let channels=inputAudit["channels"]as?UInt32 else{return "实际输入尚未就绪"}
        return "实际输入：\(name) · \(String(format:"%.0f",rate/1000)) kHz · \(channels)声道"
    }
    private let retirement=AudioRetirement()
    private var captureGeneration=UUID()
    var releasePending:Bool{retirement.pending}
    func waitForRelease()async{await retirement.wait()}
    private func isCurrentCapture(_ owner:UUID)->Bool{lock.withLock{captureGeneration==owner}}
    private var configuredAt=Date.distantPast
    private var firstBuffer:DispatchSemaphore?
    private var usableAt=Date.distantPast
    private var startupSilentFrames:Int64=0
    private var usableSeen=false
    private var writerBeforeStart=false
    var readinessAudit:[String:Any]{lock.withLock{["startup_digital_silence_seconds":Double(startupSilentFrames)/rate,"usable_audio_received":usableSeen,"capture_graph":"input_sink","writer_attached_before_start":writerBeforeStart]}}
    private var activity:NSObjectProtocol?
    var shouldHandleConfigurationChange:Bool {Date().timeIntervalSince(configuredAt)>1}
    var onLevels:(([Double])->Void)?
    var onError:((String)->Void)?
    private var receivedAt=Date.distantPast
    private var lastBufferFrames=0
    var lastBufferTime:Date {lock.lock();defer{lock.unlock()};return receivedAt}
    var stopTailSeconds:Double {lock.withLock{RecordingTail.seconds(bufferFrames:lastBufferFrames,sampleRate:rate)}}
    var isRunning:Bool {engine?.isRunning == true}
    private var actualDevice:AudioDeviceID?{
        guard let unit=engine?.inputNode.audioUnit else{return nil}
        var result=AudioDeviceID(0),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioUnitGetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&result,&size)==noErr ? result:nil
    }
    var duration:Double {lock.lock();defer{lock.unlock()};return Double(frames)/rate}
    static var authorized:Bool {AVCaptureDevice.authorizationStatus(for:.audio)       == .authorized}
    static func request() async ->Bool {await AVCaptureDevice.requestAccess(for:.audio)}
    func prepare(uid:String,preferBuiltIn:Bool,beforeStart:((AVAudioFormat)throws->Void)?=nil) throws {
        guard !releasePending else{throw AppError.message("上一段录音设备正在释放，请稍后重试。")}
        guard Self.authorized else {throw AppError.message("请先允许咸鱼说使用麦克风。")}
        let choices=AudioDevices.list()
        guard let chosen=AudioDevices.resolve(uid:uid,preferBuiltIn:preferBuiltIn,choices:choices,defaultDevice:AudioDevices.defaultInput())else{throw AppError.message(uid.isEmpty ? "系统默认麦克风不可用，请选择录音设备。":"所选麦克风已断开，请重新选择设备。")}
        // Resolve the actual default on every start, including a warm-engine reuse.
        let selected=chosen.id
        if isRunning && selected==currentUID && AudioDevices.routeMatches(actualDevice,chosen:chosen,choices:choices) && Date().timeIntervalSince(lastBufferTime)<0.5 {lock.withLock{writerBeforeStart=false};try beforeStart?(engine!.inputNode.outputFormat(forBus:0));return}
        shutdown()
        configuredAt=Date()
        let engine=AVAudioEngine(),input=engine.inputNode
        guard let unit=input.audioUnit else{throw AppError.message("无法读取麦克风设备。")}
        var device=chosen.device
        var initial=AudioDeviceID(0),initialSize=UInt32(MemoryLayout<AudioDeviceID>.size)
        let initialRead=AudioUnitGetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&initial,&initialSize)
        // Reassigning an already-correct Bluetooth HAL unit can invalidate its
        // duplex formats. Read first; only switch when the route differs.
        if (!uid.isEmpty || preferBuiltIn) && (initialRead != noErr || initial != device) {
            let code=AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&device,UInt32(MemoryLayout<AudioDeviceID>.size))
            guard code==noErr else {throw AppError.message("无法切换麦克风，请选择其他设备。")}
        }
        let format=input.outputFormat(forBus:0)
        guard format.sampleRate>0,format.channelCount>0 else {throw AppError.message("麦克风格式不可用，请重新连接设备。")}
        // A sink supplies input render demand without opening an app playback
        // stream on the headphones. The realtime block does no work; the regular
        // input tap below receives PCM outside that realtime block.
        let sink=AVAudioSinkNode{_,_,_ in noErr};engine.attach(sink)
        engine.connect(input,to:sink,format:format)
        let first=DispatchSemaphore(value:0)
        lock.lock();firstBuffer=first;usableAt=Date.distantPast;startupSilentFrames=0;usableSeen=false;lock.unlock()
        activity=ProcessInfo.processInfo.beginActivity(options:[.userInitiatedAllowingIdleSystemSleep],reason:"咸鱼说正在使用麦克风")
        rate=format.sampleRate;lock.lock();receivedAt=Date.distantPast;lock.unlock()
        let owner=lock.withLock{captureGeneration}
        input.installTap(onBus:0,bufferSize:1024,format:format) { [weak self] buffer,_ in self?.consume(buffer,owner:owner) }
        tapInstalled=true;self.engine=engine
        configurationObserver=AudioConfigurationObserver(engine:engine){[weak self] in self?.onConfigurationChange?()}
        // Attach the durable writer before the very first engine callback.
        // Previously callbacks between start() and begin() were discarded.
        do{try beforeStart?(format);lock.withLock{writerBeforeStart=beforeStart != nil}}catch{shutdown();throw error}
        engine.prepare()
        do{try engine.start()}catch{shutdown();throw error};currentUID=selected
        // AVAudioEngine resolves its default input during initialization. Verify
        // after start; do not mutate its duplex HAL unit to follow a default.
        guard AudioDevices.routeMatches(actualDevice,chosen:chosen,choices:choices)else{
            let name=actualDevice.map{AudioDevices.string($0,kAudioObjectPropertyName)} ?? "未知"
            shutdown();throw AppError.message("无法核对实际输入（\(name)）与所选麦克风（\(chosen.name)），已停止录音。")
        }
        inputAudit=["requested_mode":uid.isEmpty ? (preferBuiltIn ? "prefer_built_in":"system_default"):"explicit","actual_name":chosen.name,"actual_uid":chosen.id,"sample_rate":format.sampleRate,"channels":format.channelCount,"route_verified":true]
    }
    func waitForAudio() async ->Bool {
        let owner=lock.withLock{captureGeneration},deadline=ProcessInfo.processInfo.systemUptime+4
        // Multiple warm/start waiters may observe the same PCM. No single-use
        // semaphore, audio-thread work or blocking main-thread wait is needed.
        while !Task.isCancelled,ProcessInfo.processInfo.systemUptime<deadline{
            let status=lock.withLock{(captureGeneration==owner,Date().timeIntervalSince(usableAt)<0.5)}
            if !status.0{return false};if status.1{return true}
            do{try await Task.sleep(nanoseconds:20_000_000)}catch{return false}
        }
        return false
    }
    func begin(url:URL,uid:String,preferBuiltIn:Bool,stream:Bool=true) throws {
        try prepare(uid:uid,preferBuiltIn:preferBuiltIn){format in
            try self.attachRecording(url:url,format:format,stream:stream)
        }
    }
    private func attachRecording(url:URL,format:AVAudioFormat,stream:Bool)throws{
            let next=try AVAudioFile(forWriting:url,settings:format.settings,commonFormat:format.commonFormat,interleaved:format.isInterleaved)
            self.lock.lock();defer{self.lock.unlock()}
            self.file=next;self.frames=0;self.rate=format.sampleRate;self.completedSegments=[]
            self.streaming=stream ? try? StreamingCapture(owner:url.deletingPathExtension().lastPathComponent,format:format):nil
            self.streamingAudit=["requested":stream,"temporary_writer_ready":self.streaming != nil]
            self.streaming?.onSegment={ [weak self] segment in DispatchQueue.main.async{self?.onSegmentReady?(segment)} }
    }
    private func consume(_ buffer:AVAudioPCMBuffer,owner:UUID) {
        lock.lock();guard owner==captureGeneration else{lock.unlock();return};receivedAt=Date();lastBufferFrames=Int(buffer.frameLength);firstBuffer?.signal();firstBuffer=nil
        let usable=CaptureReadiness.hasSignal(buffer)
        if usable{usableAt=receivedAt;usableSeen=true}
        else if !usableSeen{startupSilentFrames+=Int64(buffer.frameLength)}
        if let file {do {try file.write(from:buffer);frames+=AVAudioFramePosition(buffer.frameLength);streaming?.append(buffer)}catch{self.file=nil;DispatchQueue.main.async{[weak self]in guard let self,self.isCurrentCapture(owner)else{return};self.onError?("录音写入失败，已保存的部分保留：\(error.localizedDescription)")}}}
        let update=Date().timeIntervalSince(lastMeter)>1.0/60.0
        if update {lastMeter=Date()};lock.unlock()
        guard update,let samples=buffer.floatChannelData?[0] else{return}
        let count=Int(buffer.frameLength),columns=34
        let levels=(0..<columns).map { index ->Double in
            let start=index*count/columns,end=max(start+1,(index+1)*count/columns)
            var square=0.0;for i in start..<min(end,count){square+=Double(samples[i]*samples[i])}
            let rms=sqrt(square/Double(max(1,end-start)));return min(1,max(0,(20*log10(rms+1e-8)+60)/54))
        }
        DispatchQueue.main.async{[weak self]in guard let self,self.isCurrentCapture(owner)else{return};self.onLevels?(levels)}
    }
    @discardableResult func finish(keepWarm:Bool,releaseAsynchronously:Bool=false)->Double {
        lock.lock();let seconds=Double(frames)/rate;file=nil;completedSegments=streaming?.finish() ?? []
        streamingAudit["chunks"]=completedSegments.count;streamingAudit["failure"]=streaming?.failureReason ?? ""
        streaming=nil;lock.unlock()
        if !keepWarm {shutdown(asynchronously:releaseAsynchronously)};return seconds
    }
    func shutdown(asynchronously:Bool=false) {
        configuredAt=Date()
        lock.lock();captureGeneration=UUID();file=nil;streaming=nil;firstBuffer=nil;usableAt=Date.distantPast;usableSeen=false;lock.unlock()
        let retired=engine,hadTap=tapInstalled,activityLease=activity
        configurationObserver=nil
        engine=nil;tapInstalled=false;activity=nil;currentUID="";inputAudit=[:]
        guard retired != nil || activityLease != nil else{return}
        let release={
            if hadTap{retired?.inputNode.removeTap(onBus:0)}
            retired?.stop()
            if let activityLease{ProcessInfo.processInfo.endActivity(activityLease)}
        }
        if asynchronously{retirement.submit(release,finished:{[weak self]in self?.onReleaseFinished?()})}else{release()}
    }
    deinit{shutdown()}
}
enum CaptureReadiness {
    /// This is a transport check, not speech/VAD: quiet microphone noise counts.
    /// Keep all PCM, including digital zeros, in the original recording.
    static func hasSignal(_ buffer:AVAudioPCMBuffer)->Bool{
        guard buffer.frameLength>0,let channels=buffer.floatChannelData else{return false}
        let interleaved=buffer.format.isInterleaved,count=Int(buffer.frameLength)*(interleaved ? Int(buffer.format.channelCount):1)
        for channel in 0..<(interleaved ? 1:Int(buffer.format.channelCount)){
            for i in 0..<count{let value=channels[channel][i];if value.isFinite && abs(value)>1e-8{return true}}
        }
        return false
    }
}
