import Foundation
import CoreAudio
import AudioToolbox
import Darwin

struct OutputControl:Codable,Equatable {
    var uid:String
    var kind:String
    var channel:UInt32
    var original:Double
    var muted:Double{kind=="mute" ? 1:0}
}
protocol OutputAudioBackend {
    func profile(_ uid:String)->String?
    func defaultUID()->String?
    func controls(_ uid:String)->[OutputControl]
    func volumeControls(_ uid:String)->[OutputControl]
    func read(_ control:OutputControl)->Double?
    func write(_ control:OutputControl,_ value:Double)->Bool
}
extension OutputAudioBackend {func profile(_ uid:String)->String?{nil};func volumeControls(_ uid:String)->[OutputControl]{[]}}
final class CoreOutputAudio:OutputAudioBackend {
    private func address(_ control:OutputControl)->AudioObjectPropertyAddress{
        AudioObjectPropertyAddress(mSelector:control.kind=="mute" ? kAudioDevicePropertyMute:(control.kind=="virtualVolume" ? kAudioHardwareServiceDeviceProperty_VirtualMainVolume:control.kind=="balance" ? kAudioHardwareServiceDeviceProperty_VirtualMainBalance:kAudioDevicePropertyVolumeScalar),mScope:kAudioDevicePropertyScopeOutput,mElement:control.channel)
    }
    private func uid(_ device:AudioDeviceID)->String?{
        var a=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyDeviceUID,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var value:Unmanaged<CFString>?,size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        return AudioObjectGetPropertyData(device,&a,0,nil,&size,&value)==noErr ? value.map{$0.takeRetainedValue() as String}:nil
    }
    private func device(_ uid:String)->AudioDeviceID?{
        var a=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain),size:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size)==noErr else{return nil}
        var values=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&values)==noErr else{return nil}
        return values.first{self.uid($0)==uid}
    }
    func defaultDeviceID()->AudioDeviceID?{
        var a=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain),d=AudioDeviceID(0),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&d)==noErr,d != 0 else{return nil};return d
    }
    func defaultUID()->String?{defaultDeviceID().flatMap(uid)}
    func read(_ c:OutputControl)->Double?{
        guard let d=device(c.uid)else{return nil};var a=address(c),size:UInt32=4
        if c.kind=="mute"{var value:UInt32=0;return AudioObjectGetPropertyData(d,&a,0,nil,&size,&value)==noErr ? Double(value):nil}
        var value:Float32=0;let code=AudioObjectGetPropertyData(d,&a,0,nil,&size,&value);guard code==noErr,value.isFinite,value>=0,value<=1 else{return nil};return Double(value)
    }
    func write(_ c:OutputControl,_ value:Double)->Bool{
        guard value.isFinite,value>=0,value<=1,let d=device(c.uid)else{return false};var a=address(c)
        if c.kind=="mute"{var v=UInt32(value);return AudioObjectSetPropertyData(d,&a,0,nil,4,&v)==noErr}
        var v=Float32(value);return AudioObjectSetPropertyData(d,&a,0,nil,4,&v)==noErr
    }
    private func control(_ uid:String,_ kind:String,_ channel:UInt32)->OutputControl?{
        guard let d=device(uid)else{return nil};var c=OutputControl(uid:uid,kind:kind,channel:channel,original:0),a=address(c),settable:DarwinBoolean=false
        let code=AudioObjectIsPropertySettable(d,&a,&settable)
        guard code==noErr,settable.boolValue,let original=read(c)else{return nil};c.original=original;return c
    }
    func profile(_ uid:String)->String?{
        guard let d=device(uid)else{return nil}
        var a=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain),transport:UInt32=0,size:UInt32=4
        guard AudioObjectGetPropertyData(d,&a,0,nil,&size,&transport)==noErr,transport==kAudioDeviceTransportTypeBluetooth || transport==kAudioDeviceTransportTypeBluetoothLE else{return nil}
        a.mSelector=kAudioDevicePropertyNominalSampleRate;var rate:Double=0;size=8
        guard AudioObjectGetPropertyData(d,&a,0,nil,&size,&rate)==noErr else{return nil}
        let channels=volumeControls(uid).map(\.channel),signature=channels.contains(0) ? [UInt32(0)]:channels
        return String(Int(rate))+":"+signature.map{String($0)}.joined(separator:",")
    }
    func volumeControls(_ uid:String)->[OutputControl]{
        var result:[OutputControl]=[]
        if let main=control(uid,"virtualVolume",0){result.append(main)}
        else if let master=control(uid,"volume",0){result.append(master)}
        // Virtual main volume alone preserves an already-wrong L/R ratio.
        // Prefer the device's stereo-balance control, avoiding coupled writes
        // to individual AirPods channels. Other devices retain a full fallback.
        if let balance=control(uid,"balance",0){result.append(balance)}
        else{result+=(UInt32(1)...32).compactMap{control(uid,"volume",$0)}}
        return result
    }
    func controls(_ uid:String)->[OutputControl]{
        if profile(uid) != nil,control(uid,"virtualVolume",0)==nil{return []}
        for kind in ["mute","virtualVolume","volume"]{if let master=control(uid,kind,0){return [master]}}
        guard let d=device(uid)else{return []}
        var a=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyStreamConfiguration,mScope:kAudioDevicePropertyScopeOutput,mElement:kAudioObjectPropertyElementMain),size:UInt32=0
        guard AudioObjectGetPropertyDataSize(d,&a,0,nil,&size)==noErr,size>0 else{return []}
        let memory=UnsafeMutableRawPointer.allocate(byteCount:Int(size),alignment:MemoryLayout<AudioBufferList>.alignment);defer{memory.deallocate()}
        guard AudioObjectGetPropertyData(d,&a,0,nil,&size,memory)==noErr else{return []}
        let count=UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to:AudioBufferList.self)).reduce(UInt32(0)){$0+$1.mNumberChannels}
        guard count>0,count<=32 else{return []}
        for kind in ["mute","volume"]{
            let controls=(1...count).compactMap{control(uid,kind,$0)}
            if controls.count==Int(count){return controls}
        }
        return []
    }
}
struct OutputProfileLease:Codable,Equatable {
    var uid:String;var originalProfile:String;var original:[OutputControl]
    var captureProfile:String?;var capture:[OutputControl]=[];var expectedVolumes:[OutputControl]=[]
    var userChanged=false;var unmutedByUser:Bool?;var playbackRestored=false
    var captureRestored:Bool?
    var captureRecoveryDeadline:Double?
}
struct OutputMuteJournal:Codable {var owner:String;var entries:[OutputControl];var parent:Int32?=getpid();var settleUntil:Double?;var userChanged:Bool?;var profiles:[OutputProfileLease]?;var restoreAfter:Double?;var deferredCapture:[OutputProfileLease]?}

/// A durable lease on only the controls this recording changed. Never forces
/// an original volume back over a value the user changed during the recording.
final class RecordingMuteController {
    private let backend:OutputAudioBackend
    private let journalURL:URL
    private var journal=OutputMuteJournal(owner:UUID().uuidString,entries:[])
    private var observers:[(AudioObjectPropertyAddress,AudioObjectPropertyListenerBlock)]=[]
    private var profileObserver:(AudioDeviceID,AudioObjectPropertyListenerBlock)?
    private var guardProcess:Process?
    private var guardOwner=""
    private var useWatchdog=true
    private var currentUID:String?
    private var deferredRelease=false
    private var muteSuppressed=false
    private var modeTimer:Timer?
    private var modeReady=Date.distantPast
    private var profileObserved:[String:(String,Date)]=[:]
    private var retry:DispatchWorkItem?
    private var retryDeadline=Date.distantPast
    private let now:()->Date
    private let automaticRetries:Bool
    private var lockFD:Int32 = -1
    private var recoverySkipped=false
    private var leaseUnavailable=false
    private(set) var active=false
    var onStatus:((String)->Void)?
    init(backend:OutputAudioBackend=CoreOutputAudio(),root:URL=AppPaths.root,observe:Bool=true,expectedOwner:String?=nil,now:@escaping()->Date=Date.init,automaticRetries:Bool=true){
        self.backend=backend;self.now=now;self.automaticRetries=automaticRetries;journalURL=root.appendingPathComponent("recording-mute-recovery.json")
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        lockFD=Darwin.open(root.appendingPathComponent("recording-mute.lock").path,O_CREAT|O_RDWR,0o600)
        _ = locked(fallback:false){
            if let data=try? Data(contentsOf:journalURL),let old=try? JSONDecoder().decode(OutputMuteJournal.self,from:data){
                if let expectedOwner,old.owner != expectedOwner{recoverySkipped=true;return true}
                if let parent=old.parent,parent != getpid(),parent>1,kill(parent,0)==0,!old.entries.isEmpty{leaseUnavailable=true;recoverySkipped=true;return true}
                journal=old
            }else if expectedOwner != nil{recoverySkipped=true;return true}
            restore(excluding:nil);return true
        }
        if observe{
            for selector in [kAudioHardwarePropertyDefaultOutputDevice,kAudioHardwarePropertyDevices]{
                var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
                let listener:AudioObjectPropertyListenerBlock={ [weak self] _,_ in self?.routeChanged() }
                if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,.main,listener)==noErr{observers.append((address,listener))}
            }
            refreshProfileObserver()
        }
    }
    private func refreshProfileObserver(){
        guard !observers.isEmpty,let core=backend as?CoreOutputAudio else{return}
        let device=core.defaultDeviceID()
        guard profileObserver?.0 != device else{return}
        var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyNominalSampleRate,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        if let (old,listener)=profileObserver{AudioObjectRemovePropertyListenerBlock(old,&address,.main,listener);profileObserver=nil}
        guard let device else{return}
        let listener:AudioObjectPropertyListenerBlock={ [weak self] _,_ in self?.routeChanged() }
        if AudioObjectAddPropertyListenerBlock(device,&address,.main,listener)==noErr{profileObserver=(device,listener)}
    }
    private func locked<T>(fallback:T,_ body:()->T)->T{
        guard lockFD>=0,flock(lockFD,LOCK_EX)==0 else{return fallback}
        defer{_ = flock(lockFD,LOCK_UN)};return body()
    }
    private func persist()throws{
        try FileManager.default.createDirectory(at:journalURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(journal).write(to:journalURL,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:journalURL.path)
    }
    @discardableResult func begin(enabled:Bool,watchdog:Bool=true)->Bool{
        locked(fallback:false){
        guard enabled,!leaseUnavailable else{return false};if active{return true}
        // A previous route may still be settling. Never overwrite its durable
        // original snapshot with an observed zero from an unfinished mute.
        if !journal.entries.isEmpty || !(journal.deferredCapture ?? []).isEmpty{
            restore(excluding:nil)
            let current=backend.defaultUID()
            if journal.entries.contains(where:{$0.uid==current}) || (journal.deferredCapture ?? []).contains(where:{$0.uid==current && $0.captureProfile==backend.profile($0.uid)}){
                onStatus?("上次声音恢复仍在核验，本次不更改音量。");return false
            }
        }
        let outstanding=journal.entries,oldProfiles=(journal.profiles ?? []).filter{lease in outstanding.contains{$0.uid==lease.uid}}
        let deferredCapture=journal.deferredCapture
        active=true;deferredRelease=false;muteSuppressed=false;currentUID=nil;retry?.cancel();retry=nil
        journal=OutputMuteJournal(owner:UUID().uuidString,entries:outstanding);journal.profiles=oldProfiles.isEmpty ? nil:oldProfiles
        journal.deferredCapture=deferredCapture;useWatchdog=watchdog
        do{try persist()}catch{active=false;onStatus?("无法保存声音恢复状态，本次未静音。");return false}
        let result=muteDefault()
        if watchdog,!journal.entries.isEmpty{startGuard()}
        return result
        }
    }
    private func muteDefault()->Bool{
        guard let uid=backend.defaultUID()else{onStatus?("没有可用的声音输出，录音会继续。");return false}
        currentUID=uid
        let controls=backend.controls(uid)
        guard !controls.isEmpty else{muteSuppressed=true;onStatus?("当前输出音量无法安全核验，本次录音不自动静音。");return false}
        muteSuppressed=false
        rememberProfile(uid)
        let changes=controls.filter{abs($0.original-$0.muted)>0.0001}
        guard !changes.isEmpty else{onStatus?("输出原本已静音，保持原状态。");return true}
        // Some devices couple the mute bit to their scalar volume. Persist both
        // BEFORE the first write, including across a Bluetooth profile change.
        let previousEntries=journal.entries
        for control in changes+backend.volumeControls(uid).filter({$0.original>0.0001}){
            if !journal.entries.contains(where:{$0.uid==control.uid && $0.kind==control.kind && $0.channel==control.channel}){journal.entries.append(control)}
        }
        do{try persist()}catch{active=false;journal.entries=previousEntries;beginSettlement();restore(excluding:nil);onStatus?("无法保存声音恢复状态，本次未静音。");return false}
        if useWatchdog{startGuard()}
        for control in changes{
            guard backend.write(control,control.muted)else{
                active=false;beginSettlement();restore(excluding:nil);onStatus?("静音写入失败，正在核验并恢复声音。");return false
            }
        }
        let confirmed=changes.allSatisfy{c in backend.read(c).map{abs($0-c.muted)<0.0001} ?? false}
        onStatus?(confirmed ? "录音时已静音，结束后恢复原状态。":"静音请求已发送，设备正在切换；原音量已保存。")
        return true
    }
    private func unique(_ controls:[OutputControl])->[OutputControl]{
        var result:[OutputControl]=[]
        for c in controls where !result.contains(where:{$0.uid==c.uid && $0.kind==c.kind && $0.channel==c.channel}){result.append(c)}
        return result
    }
    private func rememberProfile(_ uid:String){
        guard let profile=backend.profile(uid),!(journal.profiles ?? []).contains(where:{$0.uid==uid})else{return}
        let original=unique(backend.controls(uid)+backend.volumeControls(uid))
        journal.profiles=(journal.profiles ?? [])+[OutputProfileLease(uid:uid,originalProfile:profile,original:original)]
    }
    /// Called after real input buffers arrive: Bluetooth can replace its output
    /// controls without changing UID when capture starts.
    func captureReady(){
        guard active,!deferredRelease,!muteSuppressed else{return}
        let monitoring=locked(fallback:false){
            guard let uid=backend.defaultUID(),uid==currentUID,let profile=backend.profile(uid)else{return false}
            rememberProfile(uid);var profiles=journal.profiles ?? []
            guard let index=profiles.firstIndex(where:{$0.uid==uid})else{return false}
            var lease=profiles[index]
            if lease.captureProfile != profile{
                lease.captureProfile=profile;lease.capture=unique(backend.controls(uid)+backend.volumeControls(uid))
                lease.expectedVolumes=backend.volumeControls(uid);lease.playbackRestored=false
                for c in lease.original where !journal.entries.contains(where:{$0.uid==c.uid && $0.kind==c.kind && $0.channel==c.channel}){journal.entries.append(c)}
                profiles[index]=lease;journal.profiles=profiles
                do{try persist()}catch{onStatus?("无法保存耳机模式恢复状态，未继续更改声音。");return false}
                if useWatchdog{startGuard()}
                for c in backend.controls(uid)where abs((backend.read(c) ?? c.original)-c.muted)>0.0001{_ = backend.write(c,c.muted)}
                lease.expectedVolumes=backend.volumeControls(uid);profiles[index]=lease;journal.profiles=profiles
                modeReady=now().addingTimeInterval(0.4);try? persist()
            }else{observeCapture()}
            return true
        }
        if monitoring,automaticRetries,modeTimer==nil{modeTimer=Timer.scheduledTimer(withTimeInterval:0.15,repeats:true){[weak self]_ in self?.captureReady()}}
    }
    private func observeCapture(){
        guard let uid=backend.defaultUID(),var profiles=journal.profiles,let index=profiles.firstIndex(where:{$0.uid==uid}),profiles[index].captureProfile==backend.profile(uid)else{return}
        var lease=profiles[index]
        if now()<modeReady{
            // Brief driver initialization may reset mute once more. Do not keep
            // asserting it after this window or intercept any user media keys.
            for c in backend.controls(uid)where abs((backend.read(c) ?? c.muted)-c.muted)>0.0001{_ = backend.write(c,c.muted)}
            lease.expectedVolumes=backend.volumeControls(uid)
        }else if !lease.userChanged{
            let volumeChanged=lease.expectedVolumes.contains{c in backend.read(c).map{abs($0-c.original)>0.0001} ?? false}
            let unmuted=backend.controls(uid).contains{c in backend.read(c).map{abs($0-c.muted)>0.0001} ?? false}
            if volumeChanged || unmuted{lease.userChanged=true;if unmuted{lease.unmutedByUser=true};journal.userChanged=true}
        }
        if profiles[index] != lease{profiles[index]=lease;journal.profiles=profiles;try? persist()}
    }
    /// Keep silence through teardown. Unmuting the capture profile here caused
    /// a short music burst before the Bluetooth playback profile returned.
    func prepareForDeviceRelease()->String?{
        locked(fallback:nil){
            guard !leaseUnavailable else{return nil};if deferredRelease{return journal.owner}
            guard active else{return journal.entries.isEmpty ? nil:journal.owner}
            observeCapture();modeTimer?.invalidate();modeTimer=nil
            active=false;currentUID=nil;deferredRelease=true;retry?.cancel();retry=nil;try? persist()
            if !journal.entries.isEmpty{onStatus?("正在释放耳机录音模式，再恢复播放音量。")}
            return journal.owner
        }
    }
    /// Stop following/muting routes while CoreAudio releases the old engine.
    /// The opaque owner prevents a late callback from ending a newer recording.
    func pauseForDeviceRelease()->String?{prepareForDeviceRelease()}
    func routeChanged(){
        refreshProfileObserver()
        guard !leaseUnavailable,!deferredRelease else{return}
        if !active{retryDeadline=now().addingTimeInterval(5)}
        _ = locked(fallback:false){
        if active{
            let next=backend.defaultUID()
            if next != currentUID{restore(excluding:nil);_ = muteDefault();if useWatchdog,!journal.entries.isEmpty{startGuard()}}
            else{restore(excluding:currentUID)}
        }else{restore(excluding:nil)}
        return true
        }
    }
    func end(owner:String?=nil){
        guard !leaseUnavailable else{return}
        _ = locked(fallback:false){
            if let owner,owner != journal.owner{return false}
            modeTimer?.invalidate();modeTimer=nil
            let wasActive=active || deferredRelease
            active=false;deferredRelease=false;currentUID=nil
            if wasActive,!(journal.profiles ?? []).isEmpty{
                journal.restoreAfter=now().timeIntervalSince1970+0.25
                profileObserved=Dictionary(uniqueKeysWithValues:(journal.profiles ?? []).compactMap{lease in backend.profile(lease.uid).map{(lease.uid,($0,now()))}})
                try? persist()
            }
            if wasActive || journal.settleUntil==nil{beginSettlement()}
            restore(excluding:nil);return true
        }
    }
    private func beginSettlement(){
        if !journal.entries.isEmpty{journal.settleUntil=now().timeIntervalSince1970+1.0;retryDeadline=now().addingTimeInterval(5)}
    }
    private func scheduleRetry(){
        guard automaticRetries,!deferredRelease else{return}
        if retryDeadline==Date.distantPast{retryDeadline=now().addingTimeInterval(5)}
        guard now()<retryDeadline else{return}
        retry?.cancel();let owner=journal.owner
        let task=DispatchWorkItem{[weak self]in
            guard let self,self.journal.owner==owner,!self.deferredRelease else{return}
            _ = self.locked(fallback:false){self.restore(excluding:self.active ? self.currentUID:nil);return true}
        }
        retry=task;DispatchQueue.main.asyncAfter(deadline:.now()+0.15,execute:task)
    }
    private func restoreCapture(_ lease:OutputProfileLease)->Bool{
        guard let profile=lease.captureProfile,backend.profile(lease.uid)==profile else{return false}
        let mutes=lease.capture.filter{$0.kind=="mute"}
        let muteValues=mutes.compactMap{backend.read($0)}
        guard muteValues.count==mutes.count else{return false}
        let wasMuted=lease.original.contains{$0.kind=="mute" && $0.original==1}
        let stillMuted=muteValues.contains(1)
        if !lease.userChanged{
            let gains=lease.capture.filter{control in
                guard control.kind != "mute",control.kind != "balance",control.original>0.0001 else{return false}
                return stillMuted || mutes.isEmpty || lease.expectedVolumes.contains{
                    $0.kind==control.kind && $0.channel==control.channel && $0.original<0.0001
                }
            }
            let values=gains.compactMap{backend.read($0)}
            guard values.count==gains.count else{return false}
            let zeroed=zip(gains,values).filter{$0.1<0.0001}
            guard backend.profile(lease.uid)==profile else{return false}
            for (control,_) in zeroed{_ = backend.write(control,control.original)}
            if !zeroed.isEmpty{return false}
        }
        guard !wasMuted || lease.unmutedByUser==true else{return true}
        guard backend.profile(lease.uid)==profile else{return false}
        for (control,value) in zip(mutes,muteValues) where value==1{_ = backend.write(control,0)}
        return !stillMuted
    }
    private func restoreDeferredCapture()->Bool{
        guard !active,!deferredRelease else{return false}
        let time=now(),current=backend.defaultUID()
        var retryNeeded=false
        journal.deferredCapture=(journal.deferredCapture ?? []).filter{lease in
            guard time.timeIntervalSince1970<(lease.captureRecoveryDeadline ?? 0)else{return false}
            guard lease.uid==current,let profile=backend.profile(lease.uid)else{profileObserved.removeValue(forKey:lease.uid);return true}
            if profileObserved[lease.uid]?.0 != profile{profileObserved[lease.uid]=(profile,time)}
            guard profile==lease.captureProfile else{return true}
            guard let observed=profileObserved[lease.uid],time.timeIntervalSince(observed.1)>=0.2 else{retryNeeded=true;return true}
            let restored=restoreCapture(lease)
            retryNeeded = retryNeeded || !restored
            return !restored
        }
        return retryNeeded
    }
    private func restore(excluding uid:String?){
        if !journal.entries.isEmpty,journal.settleUntil==nil{beginSettlement()}
        if !active,!deferredRelease,!journal.entries.isEmpty,journal.restoreAfter==nil,!(journal.profiles ?? []).isEmpty{
            journal.restoreAfter=now().timeIntervalSince1970+0.25
        }
        var pending:[OutputControl]=[]
        var gainWritesThisPass=Set<String>()
        // Bluetooth profiles verify their gains before restoring the mute bit.
        let controls=journal.entries.sorted{($0.kind=="mute" ? 0:1)<($1.kind=="mute" ? 0:1)}
        for c in controls{
            if c.uid==uid{pending.append(c);continue}
            if var profiles=journal.profiles,let index=profiles.firstIndex(where:{$0.uid==c.uid}){
                var lease=profiles[index]
                let currentProfile=backend.profile(c.uid)
                if let after=journal.restoreAfter{
                    guard now().timeIntervalSince1970>=after else{pending.append(c);continue}
                    if let profile=currentProfile{
                        if profileObserved[c.uid]?.0 != profile{profileObserved[c.uid]=(profile,now());pending.append(c);continue}
                        if now().timeIntervalSince(profileObserved[c.uid]!.1)<0.2{pending.append(c);continue}
                    }
                }
                guard currentProfile==lease.originalProfile else{
                    // Another app may keep the capture profile alive. Restore its
                    // mute only after our engine is gone and the route is stable;
                    // retain the original playback snapshot for its later return.
                    if journal.restoreAfter != nil,currentProfile==lease.captureProfile,lease.captureRestored != true{
                        lease.captureRestored=restoreCapture(lease);profiles[index]=lease;journal.profiles=profiles;try? persist()
                    }
                    pending.append(c);continue
                }
                if lease.userChanged{journal.userChanged=true}
                let targets=lease.original.compactMap{control->OutputControl? in
                    if lease.userChanged && control.kind != "mute"{return nil}
                    var target=control;if target.kind=="mute" && lease.unmutedByUser==true{target.original=0};return target
                }
                if !lease.playbackRestored{
                    // A mode switch can remap a nonzero gain. It is not a manual
                    // volume edit; return the exact pre-capture playback snapshot.
                    func order(_ c:OutputControl)->Int{c.kind=="balance" ? 0:c.kind=="mute" ? 2:1}
                    let gains=targets.filter{$0.kind != "mute"}.sorted{order($0)<order($1)}
                    var gainWriteRequested=false
                    for original in gains{
                        if let value=backend.read(original),abs(value-original.original)>0.0001{
                            gainWriteRequested=true;_ = backend.write(original,original.original)
                        }
                    }
                    // CoreAudio setters can acknowledge before applying a gain.
                    // Never unmute in the same pass as a balance/volume write;
                    // a later readback must confirm the complete gain snapshot.
                    let gainsConfirmed=gains.allSatisfy{control in backend.read(control).map{abs($0-control.original)<0.0001} ?? false}
                    if gainWriteRequested{gainWritesThisPass.insert(c.uid)}
                    if gainWritesThisPass.contains(c.uid) || !gainsConfirmed{pending.append(c);continue}
                    for original in targets.filter({$0.kind=="mute"}){if let value=backend.read(original),abs(value-original.original)>0.0001{_ = backend.write(original,original.original)}}
                    lease.playbackRestored=targets.allSatisfy{control in backend.read(control).map{abs($0-control.original)<0.0001} ?? false}
                    profiles[index]=lease;journal.profiles=profiles
                    journal.settleUntil=max(journal.settleUntil ?? 0,now().timeIntervalSince1970+1.0)
                    if !lease.playbackRestored{pending.append(c);continue}
                }
                if lease.userChanged && c.kind != "mute"{continue}
                if c.kind=="mute" && lease.unmutedByUser==true{
                    if now().timeIntervalSince1970<(journal.settleUntil ?? 0){pending.append(OutputControl(uid:c.uid,kind:c.kind,channel:c.channel,original:0))}
                    continue
                }
            }
            guard let current=backend.read(c)else{pending.append(c);continue}
            if abs(current-c.original)<0.0001{
                // An asynchronous mute can land AFTER this early read. Keep the
                // lease through the settle window instead of discarding it.
                if now().timeIntervalSince1970<(journal.settleUntil ?? 0){pending.append(c)}
                continue
            }
            if abs(current-c.muted)<0.0001{
                _=backend.write(c,c.original)
                journal.settleUntil=max(journal.settleUntil ?? 0,now().timeIntervalSince1970+1.0)
                // A write acknowledgement is not a readback. Verify on a later
                // pass even if the driver appears to update synchronously.
                pending.append(c)
            }else{journal.userChanged=true}
        }
        journal.entries=pending
        // A headset may retain its own mute setting for the call profile even
        // after playback was successfully restored. Keep this separate from
        // the playback lease so the next recording can still start normally.
        let finished=(journal.profiles ?? []).filter{lease in lease.uid != uid && !pending.contains{$0.uid==lease.uid}}
        if !finished.isEmpty{
            journal.profiles=(journal.profiles ?? []).filter{lease in !finished.contains{$0.uid==lease.uid}}
            let deadline=(journal.restoreAfter ?? journal.settleUntil ?? 0)+3600
            var deferred=journal.deferredCapture ?? []
            for var lease in finished where lease.playbackRestored && lease.captureRestored != true && lease.unmutedByUser != true &&
                lease.captureProfile != nil && lease.captureProfile != lease.originalProfile && !lease.capture.isEmpty &&
                !lease.original.contains(where:{$0.kind=="mute" && $0.original==1}) {
                lease.captureRecoveryDeadline=deadline
                deferred.removeAll{$0.uid==lease.uid && $0.captureProfile==lease.captureProfile}
                deferred.append(lease)
            }
            journal.deferredCapture=deferred
        }
        let captureRetry=restoreDeferredCapture()
        if (try? persist())==nil{onStatus?("声音恢复记录暂未保存，仍会重试核对。")}else if !active{
            if pending.isEmpty && !captureRetry{retry?.cancel();retry=nil;onStatus?(journal.userChanged==true ? "已保留你手动调整后的声音状态。":"已核对并恢复录音前的声音状态。")}
            else{onStatus?("正在核验声音恢复，原音量记录已保留。")}
        }
        if captureRetry || pending.contains(where:{$0.uid != uid}){scheduleRetry()}
    }
    /// A signed, UI-free child restores the lease even if the main process dies.
    private func startGuard(){
        guard !(guardProcess?.isRunning == true && guardOwner==journal.owner),let path=Bundle.main.resourceURL?.appendingPathComponent("AudioRestoreGuard"),FileManager.default.isExecutableFile(atPath:path.path)else{return}
        let process=Process();process.executableURL=path;process.arguments=[journalURL.deletingLastPathComponent().path,journal.owner,String(getpid())]
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        do{try process.run();guardProcess=process;guardOwner=journal.owner}catch{onStatus?("录音结束会恢复声音；异常退出时下次启动恢复。")}
    }
    static func recover(root:URL,owner:String)->Bool{
        let controller=RecordingMuteController(root:root,observe:false,expectedOwner:owner)
        return controller.recoverySkipped || controller.journal.entries.isEmpty
    }
    deinit{
        retry?.cancel();modeTimer?.invalidate()
        if lockFD>=0{Darwin.close(lockFD)}
        if let (device,listener)=profileObserver{
            var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyNominalSampleRate,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(device,&address,.main,listener)
        }
        for (var address,listener)in observers{AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,.main,listener)}
    }
}
