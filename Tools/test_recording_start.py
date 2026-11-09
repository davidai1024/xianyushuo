from pathlib import Path
import tempfile,shutil,subprocess
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='DianyuStartTests-') as temp:
 d=Path(temp);s=d/'Sources';shutil.copytree(r/'Sources',s)
 p=s/'AppState.swift';p.write_text(p.read_text().replace('    func startServices(){','    func startServices(){\n        return\n',1))
 p=s/'Hotkeys.swift';p.write_text(p.read_text().replace('    init(){','    init(){\n        suppress=true;return\n',1))
 p=s/'Recorder.swift';p.write_text(p.read_text()+'''
extension Recorder {
 func testArmWriter(_ url:URL,format:AVAudioFormat)throws->UUID{
  shutdown();lock.withLock{usableAt=Date.distantPast;usableSeen=false;startupSilentFrames=0}
  try attachRecording(url:url,format:format,stream:false)
  return lock.withLock{captureGeneration}
 }
 func testFeed(_ buffer:AVAudioPCMBuffer,owner:UUID){consume(buffer,owner:owner)}
}
''')
 sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip();exe=d/'Tests'
 subprocess.run(['swiftc','-swift-version','5','-O','-g','-sanitize=address','-sdk',sdk,'-F',str(r/'build'),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(r/'build'),*map(str,sorted(s.glob('*.swift'))),str(r/'Tests/RecordingStartTests.swift'),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
