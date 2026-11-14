"""Exercise native policy forwarding with a synthetic worker and isolated app data."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sdk = os.environ.get('DIANYU_TEST_SDK') or subprocess.check_output(
    ['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
with tempfile.TemporaryDirectory(prefix='DianyuEnginePolicy-') as directory:
    base = Path(directory)
    contents = base / 'Policy.app/Contents'
    resources = contents / 'Resources'
    mac = contents / 'MacOS'
    for folder in [resources / 'Runtime/bin', resources / 'Engine', mac]:
        folder.mkdir(parents=True)
    (resources / 'Runtime/bin/python3').symlink_to(sys.executable)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleExecutable='policy-tests', CFBundleIdentifier='im.muse.dianyu.test-policy')))
    (resources / 'Engine/worker.py').write_text('''import json,sys
jobs=[]
for line in sys.stdin:
    job=json.loads(line);jobs.append(job)
    event='warmed' if job.get('action')=='prewarm' else 'configured' if job.get('action')=='configure_cleanup' else 'result'
    print(json.dumps(dict(id=job['id'],event=event,jobs=jobs,resident=True,editor_resident=False,editor_requested=False)),flush=True)
''')
    executable = mac / 'policy-tests'
    subprocess.run(['swiftc', '-swift-version', '5', '-Onone', '-target', 'arm64-apple-macosx14.0',
                    '-sdk', sdk, *[str(root / path) for path in [
                        'Sources/Domain.swift', 'Sources/Resources.swift', 'Sources/EngineClient.swift',
                        'Tests/EngineCleanupPolicyTests.swift']], '-o', str(executable)], check=True)
    subprocess.run([str(executable)], env={**os.environ, 'DIANYU_DATA_ROOT': str(base / 'data')},
                   check=True, timeout=20)
