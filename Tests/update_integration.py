"""Real Sparkle download/verify/replace/relaunch in an isolated background fixture.
HTTP loopback is a fixture-only exception. Production accepts HTTPS feeds only.
No production permissions, processes, models or data are touched.
"""
from pathlib import Path
import subprocess,json,plistlib,shutil,threading,time,http.server,functools,hashlib,os
R=Path(__file__).resolve().parents[1];B=R/'build/update-integration';B.mkdir(exist_ok=True)
C=json.loads((R/'private-signing/profile.json').read_text());events=B/'events.jsonl';events.write_text('')
ENT=R/'build/entitlements.plist'
def run(cmd,**kw):
    try:return subprocess.run([str(c)for c in cmd],check=True,**kw)
    except subprocess.CalledProcessError as e:raise SystemExit('Fixture step failed: '+Path(str(cmd[0])).name+' '+str(e.returncode))from None
def sign(path):run(['/usr/bin/codesign','--force','--sign',C['fingerprint'],'--keychain',C['keychain'],'--options','runtime','--timestamp=none','--entitlements',ENT,path],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
apps={}
for version in [1,2]:
    app=B/('v'+str(version))/'点语更新测试.app';contents=app/'Contents';mac=contents/'MacOS';frames=contents/'Frameworks';mac.mkdir(parents=True,exist_ok=True);frames.mkdir(exist_ok=True)
    fw=frames/'Sparkle.framework'
    if not fw.exists():run(['/bin/cp','-cR',R/'build/Sparkle.framework',fw])
    compile_log=(B/('compile'+str(version)+'.log')).open('w')
    run(['/usr/bin/clang','-fobjc-arc','-Wno-nullability-completeness','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk','-mmacosx-version-min=14.0','-F',R/'build','-framework','Cocoa','-framework','Sparkle','-Wl,-rpath,@executable_path/../Frameworks','-DFIXTURE_VERSION='+str(version),R/'Tests/UpdateFixture.m','-o',mac/'Fixture'],stdout=compile_log,stderr=compile_log);compile_log.close()
    info=dict(CFBundleIdentifier='im.muse.dianyu.updatefixture',CFBundleName='点语更新测试',CFBundleExecutable='Fixture',CFBundlePackageType='APPL',CFBundleVersion=str(version),CFBundleShortVersionString='0.0.'+str(version),LSUIElement=True,SUEnableAutomaticChecks=False,SUAllowsAutomaticUpdates=False,SUEnableSystemProfiling=False,SUFeedURL='http://127.0.0.1:18771/appcast.xml',SUPublicEDKey=C['update_public_key'],NSAppTransportSecurity=dict(NSAllowsLocalNetworking=True),FixtureLog=str(events))
    (contents/'Info.plist').write_bytes(plistlib.dumps(info));sign(fw);sign(app);run(['/usr/bin/codesign','--verify','--deep','--strict',app]);apps[version]=app
archive=B/'valid.zip';run(['/usr/bin/ditto','-c','-k','--keepParent',apps[2],archive])
signature=run(['/usr/bin/swift',R/'Tools/SignUpdate.swift',R/'private-signing/update-ed25519.key',archive],capture_output=True,text=True).stdout.strip()
payload=bytearray(archive.read_bytes());payload[len(payload)//2]^=1;(B/'update.zip').write_bytes(payload)
(B/'appcast.xml').write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Isolated fixture</title><item><title>2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString><enclosure url="http://127.0.0.1:18771/update.zip" length="{len(payload)}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>''')
target=B/'installed'/'点语更新测试.app';target.parent.mkdir(exist_ok=True)
if target.exists():shutil.rmtree(target)
run(['/bin/cp','-cR',apps[1],target])
class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*args):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',18771),functools.partial(Quiet,directory=str(B)))
threading.Thread(target=server.serve_forever,daemon=True).start()
def launch(label):
    log=(B/(label+'.log')).open('w')
    return subprocess.Popen([str(target/'Contents/MacOS/Fixture')],stdout=log,stderr=log)
try:
    first=launch('tampered');first.wait(timeout=90)
    bad=[json.loads(s)for s in events.read_text().splitlines()]
    reject=any(r['event']=='error'for r in bad)and plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='1'
    assert reject,'Tampered update was not explicitly rejected'
    boundary=len(bad);shutil.copyfile(archive,B/'update.zip')
    second=launch('valid');deadline=time.monotonic()+120
    success=False
    while time.monotonic()<deadline:
        rows=[json.loads(s)for s in events.read_text().splitlines()]
        if any(r['event']=='launched'and r['version']==2 for r in rows[boundary:]):success=True;break
        time.sleep(.25)
    assert success,'Valid Sparkle update did not relaunch version2'
    rows=[json.loads(s)for s in events.read_text().splitlines()]
    assert any(r['event']=='ready-to-install'for r in rows[boundary:]),'Readiness callback not observed'
    assert any(r['event']=='launched'and r['version']==2 and r['detail'].get('marker')=='existing-models-and-personal-vocabulary'for r in rows[boundary:]),'Data marker lost'
    run(['/usr/bin/codesign','--verify','--deep','--strict',target])
    report=dict(tampered_archive_rejected=reject,valid_archive_downloaded_and_relaunched=True,data_marker_preserved=True,actual_Sparkle_ready_callback_observed=True,production_app_untouched=True,scope='isolated self-signed background fixture; loopback HTTP only; not public HTTPS/DeveloperID/Gatekeeper or cross-Mac validation',events=rows)
    (B/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print('Isolated Sparkle integration passed: bad archive rejected; valid archive replaced and relaunched; data marker retained.',flush=True)
finally:server.shutdown();server.server_close()
