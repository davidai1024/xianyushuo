import Foundation
import Combine
import SwiftUI

@MainActor final class AppState:ObservableObject {
    static let shared=AppState()
    var store=Store()
    var busy=false
    func shutdown(){}
}
struct Store{var preferences=Prefs()}
struct Prefs{var updateFeed=""}
@main struct UpdateTests {
    @MainActor static func main(){
        let manager=UpdateManager.shared,app=AppState.shared
        var count=0
        for value in ["","http://updates.example.com/appcast.xml","file:///tmp/appcast.xml","https://" + "fixture-user:fixture-password@updates.example.com/appcast.xml"]{
            app.store.preferences.updateFeed=value;precondition(manager.validFeed==nil);count+=1
        }
        app.store.preferences.updateFeed="https://updates.example.com/appcast.xml"
        precondition(manager.validFeed != nil);count+=1
        app.busy=true;manager.check();precondition(manager.status.contains("先结束"));count+=1
        app.busy=false;app.store.preferences.updateFeed="";manager.check();precondition(manager.status.contains("尚未配置"));count+=1
        print("Update policy checks passed:",count,"No update network request or installation was performed.")
    }
}
