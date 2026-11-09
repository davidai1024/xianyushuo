import SwiftUI
import Sparkle

@MainActor final class UpdateManager:NSObject,ObservableObject,SPUUpdaterDelegate {
    static let shared=UpdateManager()
    @Published var status="尚未配置正式发布源；当前版本不会自动下载或替换应用。"
    private var controller:SPUStandardUpdaterController?
    private var resumeInstallation:(()->Void)?
    private var waitTimer:Timer?
    func feedURLString(for updater:SPUUpdater)->String? { validFeed }
    var validFeed:String? {
        let value=AppState.shared.store.preferences.updateFeed
        guard let url=URL(string:value),url.scheme=="https",url.host != nil,url.user==nil,url.password==nil else{return nil}
        return value
    }
    func check(){
        guard !AppState.shared.busy else {status="请先结束录音或处理，再检查更新。";return}
        guard validFeed != nil else {status="尚未配置签名发布源。当前测试版保留现有安装，不会自动替换。";return}
        if controller==nil {
            let updater=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
            do{try updater.updater.start();updater.updater.automaticallyChecksForUpdates=false;updater.updater.automaticallyDownloadsUpdates=false;controller=updater}catch{status="更新初始化失败：\(error.localizedDescription)";return}
        }
        status="正在检查已配置的签名发布源";controller?.checkForUpdates(nil)
    }
    func updater(_ updater:SPUUpdater,shouldPostponeRelaunchForUpdate item:SUAppcastItem,untilInvokingBlock installHandler:@escaping ()->Void)->Bool {
        guard AppState.shared.busy else{return false}
        resumeInstallation=installHandler;status="更新已就绪，将在当前任务保存后继续。"
        waitTimer?.invalidate();waitTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self]_ in Task{@MainActor in
            guard let self,!AppState.shared.busy else{return}
            self.waitTimer?.invalidate();self.waitTimer=nil;let resume=self.resumeInstallation;self.resumeInstallation=nil;resume?()
        }}
        return true
    }
    func updaterWillRelaunchApplication(_ updater:SPUUpdater){AppState.shared.shutdown()}
    func updater(_ updater:SPUUpdater,didAbortWithError error:Error){status="更新未完成：\(error.localizedDescription)。当前应用和本地资料保留。"}
}
struct UpdateSettingsView:View {
    @ObservedObject var app:AppState
    @ObservedObject var updates=UpdateManager.shared
    var body:some View{VStack(alignment:.leading,spacing:10){Text(updates.status).font(.caption).foregroundStyle(.secondary);Button("检查更新"){updates.check()}.disabled(app.busy)}}
}
