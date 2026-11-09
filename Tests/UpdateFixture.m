#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

#ifndef FIXTURE_VERSION
#define FIXTURE_VERSION 1
#endif

@interface Fixture : NSObject <NSApplicationDelegate,SPUUserDriver,SPUUpdaterDelegate>
@property SPUUpdater *updater;
@end
@implementation Fixture
- (void)log:(NSString *)event detail:(id)detail {
    NSString *path=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"FixtureLog"];
    NSDictionary *value=@{@"event":event,@"version":@(FIXTURE_VERSION),@"detail":detail ?: @"",@"time":@([NSDate timeIntervalSinceReferenceDate])};
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];[file seekToEndOfFile];[file writeData:data];[file writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];[file closeFile];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *folder=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DianyuUpdateFixture"];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSString *marker=[folder stringByAppendingPathComponent:@"models-and-dictionary.marker"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:marker]) [@"existing-models-and-personal-vocabulary" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self log:@"launched" detail:@{@"marker":[NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil] ?: @"missing"}];
    if (FIXTURE_VERSION>=2) {dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[NSApp terminate:nil];});return;}
    self.updater=[[SPUUpdater alloc] initWithHostBundle:[NSBundle mainBundle] applicationBundle:[NSBundle mainBundle] userDriver:self delegate:self];
    NSError *error=nil;
    if (![self.updater startUpdater:&error]) {[self log:@"initialization-error" detail:error.localizedDescription];[NSApp terminate:nil];return;}
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/2),dispatch_get_main_queue(),^{[self.updater checkForUpdates];});
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {[self log:@"checking" detail:nil];}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {[self log:@"found" detail:item.versionString];reply(SPUUserUpdateChoiceInstall);}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack {[self log:@"not-found" detail:error.localizedDescription];ack();[NSApp terminate:nil];}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack {[self log:@"error" detail:@{@"code":@(error.code),@"message":error.localizedDescription}];ack();dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[NSApp terminate:nil];});}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {[self log:@"downloading" detail:nil];}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {[self log:@"extracting" detail:nil];}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {[self log:@"ready-to-install" detail:nil];reply(SPUUserUpdateChoiceInstall);}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {[self log:@"installing" detail:@(terminated)];}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack {[self log:@"installed" detail:@(relaunched)];ack();}
- (void)dismissUpdateInstallation {}
- (void)showUpdateInFocus {}
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {[self log:@"aborted" detail:@(error.code)];}
@end
int main(int argc,char **argv){@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;[app setActivationPolicy:NSApplicationActivationPolicyProhibited];Fixture *fixture=[Fixture new];app.delegate=fixture;[app run];}return 0;}
