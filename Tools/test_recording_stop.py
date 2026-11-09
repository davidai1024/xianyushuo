"""Reproduce stop/cancel integration checks without microphone or global hotkeys.

Requires the existing build/Sparkle.framework prepared for a native app build.
No production source, user data, installed app or signing material is modified.
"""
from pathlib import Path
import subprocess,tempfile,shutil,argparse

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--test',choices=['stop','overlay','retirement'],default='stop')
args=parser.parse_args()
test={'overlay':'OverlayCompletionTests.swift','stop':'RecordingStopIntegrationTests.swift','retirement':'AudioRetirementTests.swift'}[args.test]
FRAMEWORKS=ROOT/'build'
assert (FRAMEWORKS/'Sparkle.framework').is_dir(),'Prepare the native build dependencies first.'
with tempfile.TemporaryDirectory(prefix='DianyuStopTests-')as directory:
    temporary=Path(directory);source=temporary/'Sources'
    shutil.copytree(ROOT/'Sources',source)
    path=source/'AppState.swift';text=path.read_text()
    assert '    func startServices(){'in text
    text=text.replace('    func startServices(){','    func startServices(){\n        return\n',1)
    text+='''
extension AppState {
    func testSeedEmptyCapture() throws -> UUID {
        var record=SessionRecord();record.source="test";record.status="recording"
        try store.update(record);active=record.id;latest=record.id;phase="recording";return record.id
    }
}
'''
    path.write_text(text)
    path=source/'Hotkeys.swift';text=path.read_text();assert '    init(){'in text
    path.write_text(text.replace('    init(){','    init(){\n        suppress=true;return\n',1))
    if args.test=='retirement':
        path=source/'Recorder.swift'
        path.write_text(path.read_text()+"""
extension Recorder {
    func testOpenFile(_ url:URL,format:AVAudioFormat)throws->UUID {
        lock.lock();defer{lock.unlock()}
        captureGeneration=UUID();frames=0;rate=format.sampleRate;lastMeter=Date.distantPast
        file=try AVAudioFile(forWriting:url,settings:format.settings,commonFormat:format.commonFormat,interleaved:format.isInterleaved)
        return captureGeneration
    }
    func testFeed(_ buffer:AVAudioPCMBuffer,owner:UUID){consume(buffer,owner:owner)}
}
""")
    sdk=subprocess.run(['xcrun','--sdk','macosx','--show-sdk-path'],capture_output=True,text=True,check=True).stdout.strip()
    executable=temporary/'recording-stop-tests'
    subprocess.run(['swiftc','-swift-version','5','-O','-g','-sanitize=address','-sdk',sdk,'-F',str(FRAMEWORKS),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(FRAMEWORKS),*map(str,sorted(source.glob('*.swift'))),str(ROOT/'Tests'/test),'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True)
