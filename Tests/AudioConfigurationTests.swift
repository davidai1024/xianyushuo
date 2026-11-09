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
        var received:[ObjectIdentifier]=[],allMain=true
        var observer:AudioConfigurationObserver?=AudioConfigurationObserver{identifier in received.append(identifier);allMain = allMain && Thread.isMainThread}
        let returned=DispatchSemaphore(value:0)
        DispatchQueue(label:"test.fixed.audio-engine").async{
            center.post(name:.AVAudioEngineConfigurationChange,object:engine);returned.signal()
        }
        check(returned.wait(timeout:.now()+0.5) == .success,"Fixed engine posting returns while main is still blocked")
        check(received.isEmpty,"Actor work is deferred rather than performed on the audio queue")
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
        check(received==[ObjectIdentifier(engine)] && allMain,"Identity callback reaches main actor")
        let foreign=NSObject();center.post(name:.AVAudioEngineConfigurationChange,object:foreign)
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received.count==1,"Non-engine notifications ignored")
        weak var retired:AVAudioEngine?
        autoreleasepool{
            let temporary=AVAudioEngine();retired=temporary
            center.post(name:.AVAudioEngineConfigurationChange,object:temporary)
        }
        check(retired==nil,"Pending notification never retains a retired audio engine")
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received.count==1,"Retired-engine notification is discarded before identity matching")
        observer=nil
        center.post(name:.AVAudioEngineConfigurationChange,object:engine)
        RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        check(received.count==1,"Observer removal prevents future callbacks")
        withExtendedLifetime(observer){}
        print("Audio configuration checks passed:",checks)
    }
}
