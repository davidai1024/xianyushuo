"""Isolated calendar/layout checks. Never opens the mic or production data."""
from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='DianyuStatistics-')as temp:
 sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
 base=[r/'Sources'/name for name in ['Domain.swift','Resources.swift','Hotkeys.swift','InteractionLayout.swift','StatisticsActivity.swift']]
 for name in ['ActivityGridTests','StatisticsActivityTests']:
  exe=Path(temp)/name
  subprocess.run(['swiftc','-swift-version','5','-O','-sdk',sdk,*map(str,base),str(r/'Tests'/(name+'.swift')),'-o',str(exe)],check=True)
  subprocess.run([str(exe)],check=True)
