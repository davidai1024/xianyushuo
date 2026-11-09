import Foundation
import AVFoundation

@main struct AudioConfigurationTests {
    @MainActor static func main(){
        var checks=0
        func check(_ value:Bool,_ name:String){precondition(value,name);checks+=1}
        let center=NotificationCenter.default,engine=AVAudioEngine()
        let oldReturned=DispatchSemaphore(value:0)
        let legacy=center.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:.main){_ in}
        DispatchQueue(label:"test.legacy.audio-engine").async{
            center.post(name:.AVAudioEngineConfigurationChange,object:engine);oldReturned.signal()
        }
        check(oldReturned.wait(timeout:.now()+0.15) == .timedOut,"Reproduces synchronous notification waiting on a blocked main thread")
        RunLoop.current.run(until:Date().addingTimeInterval(0.03))
        check(oldReturned.wait(timeout:.now()+0.5) == .success,"Legacy posting resumes only when main services the notification")
        center.removeObserver(legacy)
        var received:[String]=[],allMain=true
        var observer:AudioConfigurationObserver?=AudioConfigurationObserver(engine:engine){received.append("original");allMain = allMain && Thread.isMainThread}
        let returned=DispatchSemaphore(value:0)
        DispatchQueue(label:"test.fixed.audio-engine").async{
            center.post(name:.AVAudioEngineConfigurationChange,object:engine);returned.signal()
        }
        check(returned.wait(timeout:.now()+0.5) == .success,"Fixed engine posting returns while main is still blocked")
        check(received.isEmpty,"Actor work is deferred rather than performed on the audio queue")
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(received==["original"] && allMain,"Engine callback reaches main actor")
        let foreign=NSObject();center.post(name:.AVAudioEngineConfigurationChange,object:foreign)
        let replacement=AVAudioEngine()
        center.post(name:.AVAudioEngineConfigurationChange,object:replacement)
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received.count==1,"Only the observed engine can deliver notifications")
        center.post(name:.AVAudioEngineConfigurationChange,object:engine)
        weak var retiredObserver:AudioConfigurationObserver?
        retiredObserver=observer
        observer=nil
        check(retiredObserver==nil,"Pending notification does not retain the old observer")
        observer=AudioConfigurationObserver(engine:replacement){received.append("replacement")}
        center.post(name:.AVAudioEngineConfigurationChange,object:engine)
        center.post(name:.AVAudioEngineConfigurationChange,object:replacement)
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received==["original","replacement"],"Only the replacement callback runs after an engine switch")
        observer=nil
        center.post(name:.AVAudioEngineConfigurationChange,object:replacement)
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received.count==2,"Observer removal prevents future callbacks")

        weak var retired:AVAudioEngine?
        autoreleasepool{
            let temporary=AVAudioEngine();retired=temporary
            let temporaryObserver=AudioConfigurationObserver(engine:temporary){received.append("retired")}
            center.post(name:.AVAudioEngineConfigurationChange,object:temporary)
            withExtendedLifetime(temporaryObserver){}
        }
        check(retired==nil,"Pending callback does not keep an engine alive")
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received.count==2,"An engine released before dispatch leaves no callback")
        withExtendedLifetime(observer){}
        print("Audio configuration checks passed:",checks)
    }
}
