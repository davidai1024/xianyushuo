"""Isolated first-run lifecycle/layout tests. No real audio, hotkeys or services."""
from pathlib import Path
import subprocess,shutil,plistlib
a=Path(__file__).resolve().parents[1];r=a/'build/onboarding-tests';r.mkdir(parents=True,exist_ok=True);s=r/'Sources';shutil.copytree(a/'Sources',s,dirs_exist_ok=True)
p=s/'AppState.swift';p.write_text(p.read_text().replace('    func startServices(){','    func startServices(){\n        return\n',1))
p=s/'Hotkeys.swift';p.write_text(p.read_text().replace('    init(){','    init(){\n        suppress=true;return\n',1))
p=r/'Tests.swift';p.write_text((a/'Tests/OnboardingTests.swift').read_text().replace('@main ',''))
tests=['OnboardingTests','OnboardingLayoutTests']
runner=r/'Runner.swift';runner.write_text('import Foundation\n@main struct Runner { @MainActor static func main() async throws { switch CommandLine.arguments.last! {'+''.join('case "'+n+'": try await '+n+'.main();'for n in tests)+' default: fatalError() } } }')
bundle=r/'SetupTests.app';res=bundle/'Contents/Resources';mac=bundle/'Contents/MacOS';res.mkdir(parents=True,exist_ok=True);mac.mkdir(exist_ok=True)
for f in(a/'Resources').iterdir():
 if f.is_file():shutil.copy2(f,res/f.name)
(bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'im.muse.dianyu.setuptests','CFBundleExecutable':'SetupTests','CFBundlePackageType':'APPL'}))
sdk=subprocess.run(['xcrun','--sdk','macosx','--show-sdk-path'],capture_output=True,text=True,check=True).stdout.strip();out=mac/'SetupTests'
subprocess.run(['swiftc','-swift-version','5','-Onone','-g','-sanitize=address','-sdk',sdk,'-F',str(a/'build'),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(a/'build'),*map(str,sorted(s.glob('*.swift'))),str(p),str(runner),'-o',str(out)],check=True)
for test in tests:subprocess.run([str(out),test],check=True)
