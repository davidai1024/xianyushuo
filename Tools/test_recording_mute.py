"""Native mute/recovery regression tests. Fake devices, no real audio changes."""
from pathlib import Path
import subprocess,tempfile
a=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='DianyuMuteTest-')as tmp:
 exe=Path(tmp)/'mute-tests';sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
 subprocess.run(['swiftc','-swift-version','5','-O','-g','-sanitize=address','-sdk',sdk,*map(str,[a/'Sources/Domain.swift',a/'Sources/Hotkeys.swift',a/'Sources/Resources.swift',a/'Sources/RecordingMute.swift']),str(a/'Tests/RecordingMuteTests.swift'),'-F',str(a/'build'),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(a/'build'),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
