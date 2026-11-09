import Foundation

final class FakeOutputAudio:OutputAudioBackend {
    var profileNames:[String:String]=[:]
    func profile(_ uid:String)->String?{profileNames[uid]}
    var selected:String?="a",available:Set<String>=["a","b"]
    var definitions=["a":[OutputControl(uid:"a",kind:"mute",channel:0,original:0)],"b":[OutputControl(uid:"b",kind:"mute",channel:0,original:0)]]
    var values=["a.mute.0":0.0,"b.mute.0":0.0]
    var failOnce:Set<String>=[]
    var writes=0
    var actions:[(OutputControl,Double)]=[]
    var volumeDefinitions:[String:[OutputControl]]=[:]
    var coupled=false,delayWrites=false
    var queued:[(OutputControl,Double)]=[]
    func volumeControls(_ uid:String)->[OutputControl]{(volumeDefinitions[uid] ?? []).map{var c=$0;c.original=values[key(c)] ?? 0;return c}}
    func apply(_ c:OutputControl,_ value:Double){values[key(c)]=value;if coupled && c.kind=="mute" && value==1{values[c.uid+".volume.0"]=0}}
    func flush(){let jobs=queued;queued=[];for(c,v)in jobs{apply(c,v)}}
    func key(_ c:OutputControl)->String{c.uid+"."+c.kind+"."+String(c.channel)}
    func defaultUID()->String?{selected}
    func controls(_ uid:String)->[OutputControl]{guard available.contains(uid)else{return []};return (definitions[uid] ?? []).map{var c=$0;c.original=values[key(c)] ?? 0;return c}}
    func read(_ c:OutputControl)->Double?{available.contains(c.uid) ? values[key(c)]:nil}
    func write(_ c:OutputControl,_ value:Double)->Bool{
        let key=key(c);if failOnce.remove(key) != nil{return false};guard available.contains(c.uid)else{return false};writes+=1;actions.append((c,value));if delayWrites{queued.append((c,value))}else{apply(c,value)};return true
    }
}
@main struct RecordingMuteTests {
    static func main()throws{
        var count=0
        func check(_ truth:Bool,_ label:String){if !truth{FileHandle.standardError.write(Data("FAIL after \(count): \(label)\n".utf8));exit(1)};count+=1}
        let base=FileManager.default.temporaryDirectory.appendingPathComponent("RecordingMuteTests-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:base)}
        var clock=Date()
        func make(_ name:String,_ backend:FakeOutputAudio)->RecordingMuteController{RecordingMuteController(backend:backend,root:base.appendingPathComponent(name),observe:false,now:{clock},automaticRetries:false)}
        func settle(_ c:RecordingMuteController){clock=clock.addingTimeInterval(0.3);c.routeChanged();clock=clock.addingTimeInterval(1.1);c.routeChanged();clock=clock.addingTimeInterval(1.1);c.routeChanged();c.routeChanged()}
        func end(_ c:RecordingMuteController){c.end();settle(c)}
        let a=FakeOutputAudio(),c=make("basic",a)
        check(!c.begin(enabled:false,watchdog:false) && a.writes==0,"Disabled setting never touches output")
        check(c.begin(enabled:true,watchdog:false) && a.values["a.mute.0"]==1,"Recording mutes the current output")
        check(c.begin(enabled:true,watchdog:false) && a.writes==1,"Repeated starts do not overwrite the original snapshot")
        end(c);check(a.values["a.mute.0"]==0,"Ending restores originally audible state")
        end(c);check(a.writes==2,"Repeated endings do not change restored output")
        a.values["a.mute.0"]=1
        check(c.begin(enabled:true,watchdog:false),"An already-muted output counts as silent")
        end(c);check(a.values["a.mute.0"]==1 && a.writes==2,"Original mute is never undone")
        let volume=FakeOutputAudio();volume.definitions["a"]=[OutputControl(uid:"a",kind:"volume",channel:0,original:0.6)];volume.values["a.volume.0"]=0.6
        let v=make("volume",volume);check(v.begin(enabled:true,watchdog:false) && volume.values["a.volume.0"]==0,"Volume-only output has a silent fallback")
        end(v);check(volume.values["a.volume.0"]==0.6,"Original fractional volume restored exactly")
        _=v.begin(enabled:true,watchdog:false);volume.values["a.volume.0"]=0.25;end(v)
        check(volume.values["a.volume.0"]==0.25,"A user's volume adjustment is not overwritten")
        let stereo=FakeOutputAudio();stereo.definitions["a"]=(1...2).map{OutputControl(uid:"a",kind:"volume",channel:UInt32($0),original:0.4)};stereo.values["a.volume.1"]=0.4;stereo.values["a.volume.2"]=0.7
        let s=make("stereo",stereo);check(s.begin(enabled:true,watchdog:false),"Per-channel output can be muted")
        check(stereo.values["a.volume.1"]==0 && stereo.values["a.volume.2"]==0,"Every channel is silent")
        end(s);check(stereo.values["a.volume.1"]==0.4 && stereo.values["a.volume.2"]==0.7,"Stereo balance preserved")
        stereo.failOnce=["a.volume.2"];check(!s.begin(enabled:true,watchdog:false),"Partial mute failure is reported")
        check(stereo.values["a.volume.1"]==0.4 && stereo.values["a.volume.2"]==0.7,"Partial changes roll back")
        end(s)
        let route=FakeOutputAudio(),r=make("route",route)
        _=r.begin(enabled:true,watchdog:false);route.selected="b";r.routeChanged()
        check(route.values["a.mute.0"]==0 && route.values["b.mute.0"]==1,"Switching output restores old and mutes new device")
        end(r);check(route.values["b.mute.0"]==0,"New route restores on finish")
        route.selected="a";_=r.begin(enabled:true,watchdog:false);route.available.remove("a");route.selected="b";r.routeChanged();end(r)
        check(route.values["a.mute.0"]==1 && route.values["b.mute.0"]==0,"Disconnected output keeps a recoverable lease")
        route.available.insert("a");r.routeChanged();check(route.values["a.mute.0"]==0,"Reconnected output restores its prior state")
        let crash=FakeOutputAudio(),root=base.appendingPathComponent("crash"),first=RecordingMuteController(backend:crash,root:root,observe:false,now:{clock},automaticRetries:false)
        _=first.begin(enabled:true,watchdog:false)
        let second=RecordingMuteController(backend:crash,root:root,observe:false,now:{clock},automaticRetries:false)
        check(crash.values["a.mute.0"]==0,"Startup recovers a stale recording lease")
        settle(second)
        _=second.begin(enabled:true,watchdog:false)
        let staleGuard=RecordingMuteController(backend:crash,root:root,observe:false,expectedOwner:"stale",now:{clock},automaticRetries:false)
        check(crash.values["a.mute.0"]==1,"Old guard cannot restore a new recording's lease")
        end(second);withExtendedLifetime(staleGuard){}
        let coupled=FakeOutputAudio();coupled.coupled=true;coupled.values["a.volume.0"]=0.62
        coupled.volumeDefinitions["a"]=[OutputControl(uid:"a",kind:"volume",channel:0,original:0.62)]
        let coupledController=make("coupled",coupled)
        _=coupledController.begin(enabled:true,watchdog:false)
        check(coupled.values["a.mute.0"]==1 && coupled.values["a.volume.0"]==0,"Driver can couple mute to zero scalar volume")
        end(coupledController)
        check(coupled.values["a.mute.0"]==0 && coupled.values["a.volume.0"]==0.62,"Mute flag AND original scalar volume restored")
        _=coupledController.begin(enabled:true,watchdog:false);coupled.values["a.volume.0"]=0.24;end(coupledController)
        check(coupled.values["a.volume.0"]==0.24,"Manual volume override survives coupled-mute recovery")
        let delayed=FakeOutputAudio();delayed.delayWrites=true;delayed.coupled=true;delayed.values["a.volume.0"]=0.55
        delayed.volumeDefinitions["a"]=[OutputControl(uid:"a",kind:"volume",channel:0,original:0.55)]
        let delayedController=make("delayed",delayed);var statuses:[String]=[];delayedController.onStatus={statuses.append($0)}
        check(delayedController.begin(enabled:true,watchdog:false),"Accepted asynchronous mute retains recovery lease")
        delayedController.end()
        check(!statuses.contains(where:{$0.contains("已核对并恢复")}),"Old readback cannot claim successful restoration")
        delayed.flush();check(delayed.values["a.volume.0"]==0,"Late mute reproduces headphone volume stuck at zero")
        delayedController.routeChanged();delayed.flush();settle(delayedController)
        check(delayed.values["a.mute.0"]==0 && delayed.values["a.volume.0"]==0.55,"Delayed write eventually restores full original snapshot")
        check(statuses.last?.contains("已核对并恢复")==true,"Success emitted only after settled readback")
        let retired=FakeOutputAudio(),retiredController=make("retired",retired)
        _=retiredController.begin(enabled:true,watchdog:false);let oldLease=retiredController.pauseForDeviceRelease()!
        let writesBeforeRelease=retired.writes;retiredController.routeChanged()
        check(retired.writes==writesBeforeRelease && retired.values["a.mute.0"]==1,"Profile handoff never restores before exclusive engine retirement")
        retiredController.end(owner:oldLease);settle(retiredController)
        check(retired.values["a.mute.0"]==0,"Post-retirement callback restores saved state")
        _=retiredController.begin(enabled:true,watchdog:false);retiredController.end(owner:oldLease)
        check(retiredController.active && retired.values["a.mute.0"]==1,"Late prior owner cannot unmute the next recording")
        end(retiredController)
        let failure=FakeOutputAudio(),failureController=make("restorefailure",failure)
        _=failureController.begin(enabled:true,watchdog:false);failure.failOnce=["a.mute.0"]
        failureController.end();check(failure.values["a.mute.0"]==1,"Failed restoration remains pending")
        settle(failureController);check(failure.values["a.mute.0"]==0,"Retry recovers a failed restore write")
        let rapid=FakeOutputAudio(),rapidController=make("rapid",rapid)
        _=rapidController.begin(enabled:true,watchdog:false);rapidController.end();let countBefore=rapid.writes
        check(!rapidController.begin(enabled:true,watchdog:false) && rapid.writes==countBefore,"Rapid recording cannot replace an unsettled original snapshot")
        settle(rapidController);check(rapidController.begin(enabled:true,watchdog:false),"New mute allowed after verified settlement");end(rapidController)
        func stereoProfile(_ output:FakeOutputAudio,_ level:Double,_ muted:Double=0){
            output.profileNames["a"]="48000:1,2";output.values.removeValue(forKey:"a.volume.0")
            output.values["a.volume.1"]=level;output.values["a.volume.2"]=level;output.values["a.mute.0"]=muted
            output.volumeDefinitions["a"]=(1...2).map{OutputControl(uid:"a",kind:"volume",channel:UInt32($0),original:level)}
        }
        func captureProfile(_ output:FakeOutputAudio,_ level:Double=0.53){
            output.profileNames["a"]="24000:0";output.values.removeValue(forKey:"a.volume.1");output.values.removeValue(forKey:"a.volume.2")
            output.values["a.volume.0"]=level;output.values["a.mute.0"]=0
            output.volumeDefinitions["a"]=[OutputControl(uid:"a",kind:"volume",channel:0,original:level)]
        }
        let profile=FakeOutputAudio();stereoProfile(profile,0.377);let profileController=make("profiles",profile)
        _=profileController.begin(enabled:true,watchdog:false);captureProfile(profile)
        check(profile.values["a.mute.0"]==0,"Actual driver profile replacement resets mute while UID is unchanged")
        profileController.captureReady();check(profile.values["a.mute.0"]==1,"Real-buffer readiness reasserts mute on the capture profile")
        let profileOwner=profileController.prepareForDeviceRelease()!
        check(profile.values["a.mute.0"]==1,"Capture stays muted until hardware release finishes: no premature music burst")
        stereoProfile(profile,0.481);profileController.end(owner:profileOwner);settle(profileController)
        check(profile.values["a.volume.1"]==0.377 && profile.values["a.volume.2"]==0.377,"Nonzero driver gain remapping returns to exact playback snapshot")
        let profileRoot=base.appendingPathComponent("profiles")
        let journalURL=profileRoot.appendingPathComponent("recording-mute-recovery.json")
        let restoredPlayback=try JSONDecoder().decode(OutputMuteJournal.self,from:Data(contentsOf:journalURL))
        check(restoredPlayback.entries.isEmpty && restoredPlayback.deferredCapture?.count==1,"Playback completion keeps an independent pending capture recovery")
        let restartRoot=base.appendingPathComponent("meeting-restart")
        try FileManager.default.createDirectory(at:restartRoot,withIntermediateDirectories:true)
        let restartJournal=restartRoot.appendingPathComponent("recording-mute-recovery.json")
        try JSONEncoder().encode(restoredPlayback).write(to:restartJournal)
        let meeting=FakeOutputAudio();stereoProfile(meeting,0.377)
        let restart=make("meeting-restart",meeting)
        captureProfile(meeting,0);meeting.values["a.mute.0"]=1
        let beforeMeetingWrites=meeting.writes
        restart.routeChanged()
        check(meeting.writes==beforeMeetingWrites,"An external meeting's newly changing profile is allowed to settle")
        clock=clock.addingTimeInterval(0.3);restart.routeChanged()
        check(meeting.values["a.volume.0"]==0.53 && meeting.values["a.mute.0"]==1,"Restore the old app-owned capture zero before unmuting")
        restart.routeChanged();restart.routeChanged()
        check(meeting.values["a.mute.0"]==0,"An external meeting can reuse the capture profile after playback and an app restart")
        let recovered=try JSONDecoder().decode(OutputMuteJournal.self,from:Data(contentsOf:restartJournal))
        check(recovered.deferredCapture?.isEmpty==true,"Confirmed capture recovery is consumed once")
        meeting.values["a.mute.0"]=1;meeting.values["a.volume.0"]=0
        let manualMeetingWrites=meeting.writes;restart.routeChanged()
        check(meeting.writes==manualMeetingWrites,"After recovery, a user's new meeting mute and zero remain untouched")
        let legacy=FakeOutputAudio();stereoProfile(legacy,0.55)
        let legacyRoot=base.appendingPathComponent("legacy-capture-recovery")
        try FileManager.default.createDirectory(at:legacyRoot,withIntermediateDirectories:true)
        var legacyJournal=restoredPlayback
        legacyJournal.deferredCapture=nil;legacyJournal.profiles=restoredPlayback.deferredCapture
        legacyJournal.restoreAfter=clock.timeIntervalSince1970
        try JSONEncoder().encode(legacyJournal).write(to:legacyRoot.appendingPathComponent("recording-mute-recovery.json"))
        let migratedRecovery=make("legacy-capture-recovery",legacy)
        captureProfile(legacy,0);legacy.values["a.mute.0"]=1
        migratedRecovery.routeChanged();clock=clock.addingTimeInterval(0.3)
        migratedRecovery.routeChanged();migratedRecovery.routeChanged();migratedRecovery.routeChanged()
        check(legacy.values["a.mute.0"]==0 && legacy.values["a.volume.0"]==0.53,"Legacy journal with no playback entries recovers the capture profile")
        legacyJournal.restoreAfter=clock.timeIntervalSince1970-3700
        try JSONEncoder().encode(legacyJournal).write(to:legacyRoot.appendingPathComponent("recording-mute-recovery.json"))
        legacy.values["a.mute.0"]=1;legacy.values["a.volume.0"]=0
        let expiredRecovery=make("legacy-capture-recovery",legacy)
        let staleWrites=legacy.writes;settle(expiredRecovery)
        check(legacy.writes==staleWrites,"Expired capture evidence never overwrites current controls")
        let held=FakeOutputAudio();stereoProfile(held,0.39);let heldController=make("held-capture",held)
        _=heldController.begin(enabled:true,watchdog:false);captureProfile(held);heldController.captureReady()
        let heldOwner=heldController.prepareForDeviceRelease()!
        check(held.values["a.mute.0"]==1,"Preparing release never opens the capture output")
        heldController.end(owner:heldOwner)
        check(held.values["a.mute.0"]==1,"Post-release Bluetooth settling remains quiet")
        clock=clock.addingTimeInterval(0.3);heldController.routeChanged()
        check(held.values["a.mute.0"]==0,"An external mic holder cannot strand the stable capture profile on mute")
        stereoProfile(held,0.72,1);heldController.routeChanged()
        check(held.values["a.mute.0"]==1,"A newly switching playback route is not restored prematurely")
        clock=clock.addingTimeInterval(0.3);heldController.routeChanged();settle(heldController)
        check(held.values["a.mute.0"]==0 && held.values["a.volume.1"]==0.39 && held.values["a.volume.2"]==0.39,"Stable playback restores the original complete stereo snapshot")
        let skew=FakeOutputAudio();stereoProfile(skew,0.6)
        skew.values["a.virtualVolume.0"]=0.6
        skew.volumeDefinitions["a"]!.insert(OutputControl(uid:"a",kind:"virtualVolume",channel:0,original:0.6),at:0)
        let skewController=make("real-skew",skew);_=skewController.begin(enabled:true,watchdog:false)
        captureProfile(skew);skewController.captureReady();let skewOwner=skewController.prepareForDeviceRelease()!
        stereoProfile(skew,0.6,1);skew.values["a.volume.1"]=0.2152252;skew.values["a.virtualVolume.0"]=0.6
        skew.volumeDefinitions["a"]!.insert(OutputControl(uid:"a",kind:"virtualVolume",channel:0,original:0.6),at:0)
        let actionStart=skew.actions.count;skewController.end(owner:skewOwner);settle(skewController)
        check(skew.values["a.volume.1"]==0.6 && skew.values["a.volume.2"]==0.6,"Equal total volume cannot hide the reproduced AirPods L21.5/R60 skew")
        let actions=Array(skew.actions.dropFirst(actionStart))
        check(actions.last?.0.kind=="mute" && actions.last?.1==0,"Restore stereo gains before unmuting music")
        let balanceAPI=FakeOutputAudio(),balanceController=make("balance-api",balanceAPI)
        let balanceControls=[OutputControl(uid:"a",kind:"virtualVolume",channel:0,original:0.6),OutputControl(uid:"a",kind:"balance",channel:0,original:0.5)]
        func virtualStereo(_ balance:Double){balanceAPI.profileNames["a"]="48000:0";balanceAPI.volumeDefinitions["a"]=balanceControls;balanceAPI.values["a.virtualVolume.0"]=0.6;balanceAPI.values["a.balance.0"]=balance;balanceAPI.values["a.mute.0"]=1}
        virtualStereo(0.5);balanceAPI.values["a.mute.0"]=0
        _=balanceController.begin(enabled:true,watchdog:false);captureProfile(balanceAPI);balanceController.captureReady();let balanceOwner=balanceController.prepareForDeviceRelease()!
        virtualStereo(0.82);balanceController.end(owner:balanceOwner);settle(balanceController)
        check(balanceAPI.values["a.balance.0"]==0.5 && balanceAPI.values["a.virtualVolume.0"]==0.6,"The canonical balance API repairs ratio without coupled per-channel writes")
        virtualStereo(0.3);balanceAPI.values["a.mute.0"]=0
        _=balanceController.begin(enabled:true,watchdog:false);captureProfile(balanceAPI);balanceController.captureReady();let chosenBalance=balanceController.prepareForDeviceRelease()!
        virtualStereo(0.82);balanceController.end(owner:chosenBalance);settle(balanceController)
        check(balanceAPI.values["a.balance.0"]==0.3,"An intentional asymmetric user balance is preserved rather than always centered")
        let asynchronous=FakeOutputAudio(),asynchronousController=make("async-playback-gains",asynchronous)
        asynchronous.profileNames["a"]="48000:0";asynchronous.volumeDefinitions["a"]=balanceControls
        asynchronous.values["a.virtualVolume.0"]=0.6;asynchronous.values["a.balance.0"]=0.5
        _=asynchronousController.begin(enabled:true,watchdog:false)
        captureProfile(asynchronous);asynchronousController.captureReady();let asyncOwner=asynchronousController.prepareForDeviceRelease()!
        asynchronous.profileNames["a"]="48000:0";asynchronous.volumeDefinitions["a"]=balanceControls
        asynchronous.values["a.virtualVolume.0"]=0.72;asynchronous.values["a.balance.0"]=0.82;asynchronous.values["a.mute.0"]=1
        asynchronous.delayWrites=true;asynchronousController.end(owner:asyncOwner)
        clock=clock.addingTimeInterval(0.3);asynchronousController.routeChanged()
        check(asynchronous.queued.contains{$0.0.kind=="balance"},"Playback balance repair is requested asynchronously")
        check(!asynchronous.queued.contains{$0.0.kind=="mute" && $0.1==0},"Pending gain writes cannot queue an early music unmute")
        asynchronousController.routeChanged()
        check(!asynchronous.queued.contains{$0.0.kind=="mute" && $0.1==0},"Another pending control in the same restore pass cannot bypass the gain barrier")
        asynchronous.flush();asynchronousController.routeChanged()
        check(asynchronous.values["a.mute.0"]==1 && asynchronous.queued.contains{$0.0.kind=="mute" && $0.1==0},"Only a later confirmed gain readback allows unmute")
        asynchronous.flush();settle(asynchronousController)
        check(asynchronous.values["a.balance.0"]==0.5 && asynchronous.values["a.virtualVolume.0"]==0.6 && asynchronous.values["a.mute.0"]==0,"Delayed playback writes restore the entire original snapshot")
        let profileWrites=profile.writes
        _=profileController.begin(enabled:false,watchdog:false);_=profileController.prepareForDeviceRelease();profileController.end()
        check(profile.writes==profileWrites,"Disabled recording cannot replay a stale profile snapshot")
        _=profileController.begin(enabled:true,watchdog:false);captureProfile(profile);profileController.captureReady();clock=clock.addingTimeInterval(0.5)
        profile.values["a.volume.0"]=0.2;profile.values["a.mute.0"]=0;profileController.captureReady()
        let manualOwner=profileController.prepareForDeviceRelease()!;stereoProfile(profile,0.11)
        profileController.end(owner:manualOwner);settle(profileController)
        check(profile.values["a.volume.1"]==0.11 && profile.values["a.mute.0"]==0,"Manual edit during capture survives the driver's cross-profile mapping")
        stereoProfile(profile,0.3,1);_=profileController.begin(enabled:true,watchdog:false);captureProfile(profile);profileController.captureReady()
        check(profile.values["a.mute.0"]==1,"Originally muted playback remains quiet in the new capture profile")
        let mutedOwner=profileController.prepareForDeviceRelease()!;stereoProfile(profile,0.8)
        profileController.end(owner:mutedOwner);settle(profileController)
        check(profile.values["a.mute.0"]==1 && profile.values["a.volume.1"]==0.3,"Originally muted flag and exact playback level both restored")
        let modeCrash=FakeOutputAudio();stereoProfile(modeCrash,0.42)
        let modeRoot=base.appendingPathComponent("mode-crash"),modeFirst=RecordingMuteController(backend:modeCrash,root:modeRoot,observe:false,now:{clock},automaticRetries:false)
        _=modeFirst.begin(enabled:true,watchdog:false);captureProfile(modeCrash);modeFirst.captureReady();stereoProfile(modeCrash,0.7)
        let modeRecovered=RecordingMuteController(backend:modeCrash,root:modeRoot,observe:false,now:{clock},automaticRetries:false)
        settle(modeRecovered)
        check(modeCrash.values["a.volume.1"]==0.42 && modeCrash.values["a.mute.0"]==0,"Crash recovery understands persisted playback and capture profiles")
        stereoProfile(profile,0.3);_=profileController.begin(enabled:true,watchdog:false);captureProfile(profile);profileController.captureReady();clock=clock.addingTimeInterval(0.5)
        profile.values["a.volume.0"]=0.21;profileController.captureReady()
        let volumeOnlyOwner=profileController.prepareForDeviceRelease()!;stereoProfile(profile,0.12,1)
        profileController.end(owner:volumeOnlyOwner);settle(profileController)
        check(profile.values["a.volume.1"]==0.12 && profile.values["a.mute.0"]==0,"Volume override does not strand the independently cached playback mute flag")
        stereoProfile(profile,0.3,1);_=profileController.begin(enabled:true,watchdog:false);captureProfile(profile);profileController.captureReady();clock=clock.addingTimeInterval(0.5)
        profile.values["a.mute.0"]=0;profileController.captureReady()
        let unmutedOwner=profileController.prepareForDeviceRelease()!;stereoProfile(profile,0.12,1)
        profileController.end(owner:unmutedOwner);settle(profileController)
        check(profile.values["a.mute.0"]==0,"Explicit manual unmute survives a previously-muted playback profile")
        let offline=FakeOutputAudio(),offlineController=make("offline-other",offline)
        _=offlineController.begin(enabled:true,watchdog:false);offline.available.remove("a");offlineController.end();offline.selected="b"
        check(offlineController.begin(enabled:true,watchdog:false) && offline.values["b.mute.0"]==1,"Offline old headset recovery does not disable a different wired output")
        end(offlineController);offline.available.insert("a");offlineController.routeChanged();settle(offlineController)
        check(offline.values["a.mute.0"]==0 && offline.values["b.mute.0"]==0,"Both device snapshots remain recoverable")
        let unavailableMode=FakeOutputAudio();unavailableMode.profileNames["a"]="48000:0";unavailableMode.definitions["a"]=[]
        let unavailableController=make("unavailable-profile",unavailableMode)
        _=unavailableController.begin(enabled:true,watchdog:false);unavailableMode.definitions["a"]=[OutputControl(uid:"a",kind:"mute",channel:0,original:0)];unavailableMode.profileNames["a"]="24000:0"
        unavailableController.captureReady();check(unavailableMode.writes==0,"Unverifiable initial playback state cannot be muted later after a profile change");end(unavailableController)
        let unsupported=FakeOutputAudio();unsupported.definitions["a"]=[]
        let u=make("unsupported",unsupported);check(!u.begin(enabled:true,watchdog:false) && unsupported.writes==0,"Unsupported hardware is not guessed at")
        end(u);unsupported.selected=nil;check(!u.begin(enabled:true,watchdog:false),"Missing output fails safely");end(u)
        let old=Data("{\"cleanup\":\"light\"}".utf8),migrated=try JSONDecoder().decode(Preferences.self,from:old)
        check(migrated.muteWhileRecording,"Older preferences enable the newly requested setting")
        var disabled=migrated;disabled.muteWhileRecording=false
        check(!(try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(disabled))).muteWhileRecording,"Disabled choice survives restart")
        check(OverlayLayout.dismissDelay(phase:"result",delivery:"verified")==0.25,"Verified success disappears 250ms after confirmation")
        check(OverlayLayout.dismissDelay(phase:"working",delivery:"verified")==nil,"Prior success cannot hide active work")
        check(OverlayLayout.dismissDelay(phase:"result",delivery:"unverified")==nil,"Unconfirmed insertion remains recoverable")
        check(OverlayLayout.dismissDelay(phase:"error",delivery:"verified")==nil,"Errors never get hidden as successes")
        check(OverlayLayout.dismissDelay(phase:"result",delivery:"saved",cancelled:true)==0.7,"Cancellation also clears promptly")
        print("Mute lease/recovery/preferences/dismissal checks passed:",count)
    }
}
