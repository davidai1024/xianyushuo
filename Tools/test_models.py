from pathlib import Path
import subprocess,shutil,plistlib,argparse
parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group();group.add_argument('--full-download',action='store_true');group.add_argument('--input-ui',action='store_true');args=parser.parse_args()
a=Path(__file__).resolve().parents[1];r=a/'build'/('model-full-tests' if args.full_download else 'input-ui-tests' if args.input_ui else 'model-tests');r.mkdir(parents=True,exist_ok=True);s=r/'test-sources';shutil.copytree(a/'Sources',s,dirs_exist_ok=True)
p=s/'AppState.swift';p.write_text(p.read_text().replace('    func startServices(){','    func startServices(){\n        return\n',1))
p=s/'Hotkeys.swift';p.write_text(p.read_text().replace('    init(){','    init(){\n        suppress=true;return\n',1))
tests=['DeliveryEvidenceTests','DomainTests','NativeLifecycleTests','StatusMenuTests','AudioConfigurationTests','HeadphoneStreamingTests','ModelDownloadTests']
if args.full_download:tests=['ModelFullDownloadTests']
if args.input_ui:tests=['CorrectionLearningTests','CorrectionEditingTraceTests','CapsuleMotionTests','CapsuleVisibilityTests','DeliveryEvidenceTests','ModelDownloadTests']
files=[]
for name in tests:
 p=r/(name+'.swift');p.write_text((a/'Tests'/(name+'.swift')).read_text().replace('@main ',''));files.append(p)
runner=r/'Runner.swift';runner.write_text('import Foundation\n@main struct Runner { @MainActor static func main() async throws { switch CommandLine.arguments.last! {'+''.join('case "'+n+'": '+('try await ' if n in ['ModelDownloadTests','ModelFullDownloadTests']else 'try ')+n+'.main();'for n in tests)+' default: fatalError() } } }')
bundle=r/'ModelTests.app';resources=bundle/'Contents/Resources';resources.mkdir(parents=True,exist_ok=True);mac=bundle/'Contents/MacOS';mac.mkdir(exist_ok=True)
for name in ['ModelManifest.json','ModelSources.json']:shutil.copy2(a/'Resources'/name,resources/name)
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'im.muse.dianyu.modeltests','CFBundleExecutable':'ModelTests','CFBundlePackageType':'APPL'}))
sdk=subprocess.run(['xcrun','--sdk','macosx','--show-sdk-path'],capture_output=True,text=True,check=True).stdout.strip();out=mac/'ModelTests'
subprocess.run(['swiftc','-swift-version','5','-O','-g','-sanitize=address','-sdk',sdk,'-F',str(a/'build'),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(a/'build'),*map(str,sorted(s.glob('*.swift'))),*map(str,files),str(runner),'-o',str(out)],check=True)
for name in tests:subprocess.run([str(out),name],check=True)
