"""Replay a local voice file as a completed setup capture in isolated storage.
No real microphone, OS hotkeys, or external application insertion is used.
"""
from pathlib import Path
import subprocess,shutil,plistlib,argparse
p=argparse.ArgumentParser();p.add_argument('--audio',type=Path,required=True);p.add_argument('--vocabulary',type=Path,required=True);p.add_argument('--models',type=Path,required=True);args=p.parse_args()
a=Path(__file__).resolve().parents[1];r=a/'build/onboarding-audio-tests';r.mkdir(parents=True,exist_ok=True);s=r/'Sources';shutil.copytree(a/'Sources',s,dirs_exist_ok=True)
p=s/'AppState.swift';text=p.read_text().replace('    func startServices(){','    func startServices(){\n        return\n',1)
helper='''
    func testRunSetupAudio(_ source:URL)throws->UUID{
        var record=SessionRecord();record.source="onboarding";record.cleanup = .light;record.words=store.activeWords
        record.audioFile=record.id.uuidString+".wav";try FileManager.default.copyItem(at:source,to:AppPaths.audio.appendingPathComponent(record.audioFile))
        try store.update(record);latest=record.id;active=record.id;phase="working";processingStarted=Date()
        run(record,autoDeliver:record.source != "onboarding");return record.id
    }
'''
text=text.rsplit('\n}',1)[0]+helper+'\n}\n';p.write_text(text)
p=s/'Hotkeys.swift';p.write_text(p.read_text().replace('    init(){','    init(){\n        suppress=true;return\n',1))
p=s/'Delivery.swift';text=p.read_text();needle='    static func deliver(';index=text.index(needle);body=text.index('{',index)
# Instrument the delivery entry, returning before any actual UI or pasteboard action.
text=text[:body+1]+'\n        setupExternalDeliveryCalls+=1\n        return DeliveryReceipt(state:"saved",message:"isolated delivery guard",audit:[:])\n'+text[body+1:]
p.write_text('var setupExternalDeliveryCalls=0\n'+text)
bundle=r/'SetupAudioTests.app';res=bundle/'Contents/Resources';mac=bundle/'Contents/MacOS';res.mkdir(parents=True,exist_ok=True);mac.mkdir(exist_ok=True)
for name in ['Runtime','PythonExtras','Engine']:
 dst=res/name
 if dst.is_symlink():dst.unlink()
 elif dst.exists():shutil.rmtree(dst)
 dst.symlink_to(a/'build/咸鱼说.app/Contents/Resources'/name,target_is_directory=True)
for name in ['ModelManifest.json','ModelSources.json']:shutil.copy2(a/'Resources'/name,res/name)
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'im.muse.dianyu.setupaudiotests','CFBundleExecutable':'SetupAudioTests','CFBundlePackageType':'APPL'}))
sdk=subprocess.run(['xcrun','--sdk','macosx','--show-sdk-path'],capture_output=True,text=True,check=True).stdout.strip();out=mac/'SetupAudioTests'
subprocess.run(['swiftc','-swift-version','5','-Onone','-g','-sanitize=address','-sdk',sdk,'-F',str(a/'build'),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(a/'build'),*map(str,sorted(s.glob('*.swift'))),str(a/'Tests/OnboardingAudioTests.swift'),'-o',str(out)],check=True)
subprocess.run([str(out),str(args.audio.resolve()),str(args.vocabulary.resolve()),str(args.models.resolve())],check=True)
