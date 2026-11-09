from pathlib import Path
import subprocess,json,secrets,os,plistlib,shutil,sys,argparse
ROOT=Path(__file__).resolve().parents[1];B=ROOT/'build';B.mkdir(exist_ok=True)
P=argparse.ArgumentParser();P.add_argument('--initialize-signing',action='store_true');P.add_argument('--compile-only',action='store_true');P.add_argument('--version',default='0.1.0');P.add_argument('--build',default='1');args=P.parse_args()
SIGN=ROOT/'private-signing';profile=SIGN/'profile.json'
def run(cmd,**kw):
    try:return subprocess.run([str(x)for x in cmd],check=True,**kw)
    except subprocess.CalledProcessError as e:raise SystemExit('Build step failed: '+Path(str(cmd[0])).name+' (exit '+str(e.returncode)+'). Sensitive command arguments omitted.')from None
if not profile.exists() and not args.compile_only:
    if not args.initialize_signing:raise SystemExit('Fixed signing material missing. Refusing ad-hoc fallback. First creation requires --initialize-signing.')
    if any(Path('/Applications',name+'.app').exists() for name in ['点语','咸鱼说']):raise SystemExit('An installed app already exists but its fixed signing profile is missing. Restore the original profile; do not silently create a new identity.')
    if SIGN.exists():raise SystemExit('Partial signing material exists. Inspect it; do not silently replace the identity.')
    SIGN.mkdir(mode=0o700)
    password=secrets.token_urlsafe(40);key=SIGN/'identity.key';cert=SIGN/'identity.pem';p12=SIGN/'identity.p12';keychain=SIGN/'dianyu.keychain-db'
    cfg=SIGN/'openssl.cnf';cfg.write_text('[req]\ndistinguished_name=dn\nx509_extensions=extensions\nprompt=no\n[dn]\nCN=Dianyu Local Development\nO=Dianyu\n[extensions]\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nsubjectKeyIdentifier=hash\n')
    env={**os.environ,'DIANYU_P12_PASSWORD':password}
    run(['/usr/bin/openssl','req','-new','-newkey','rsa:2048','-nodes','-x509','-sha256','-days','3650','-config',cfg,'-keyout',key,'-out',cert],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    key.chmod(0o600)
    run(['/usr/bin/openssl','pkcs12','-export','-inkey',key,'-in',cert,'-out',p12,'-passout','env:DIANYU_P12_PASSWORD'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE);p12.chmod(0o600)
    run(['/usr/bin/security','create-keychain','-p',password,keychain],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    run(['/usr/bin/security','set-keychain-settings','-lut','86400',keychain],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    run(['/usr/bin/security','unlock-keychain','-p',password,keychain],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    run(['/usr/bin/security','import',p12,'-k',keychain,'-P',password,'-T','/usr/bin/codesign'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    run(['/usr/bin/security','set-key-partition-list','-S','apple-tool:,apple:,codesign:','-s','-k',password,keychain],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    result=run(['/usr/bin/openssl','x509','-in',cert,'-noout','-fingerprint','-sha1'],capture_output=True,text=True).stdout
    fingerprint=result.split('=',1)[1].replace(':','').strip()
    public=run(['/usr/bin/swift',ROOT/'Tools/GenerateUpdateKey.swift',SIGN/'update-ed25519.key'],capture_output=True,text=True).stdout.strip()
    profile.write_text(json.dumps(dict(keychain=str(keychain),password=password,fingerprint=fingerprint,update_public_key=public)));profile.chmod(0o600)
    print('Created a dedicated fixed LOCAL signing identity and update key; no system trust changes.')
app=B/'咸鱼说.app';contents=app/'Contents';mac=contents/'MacOS';resources=contents/'Resources';frameworks=contents/'Frameworks'
for folder in [mac,resources,frameworks]:folder.mkdir(parents=True,exist_ok=True)
sources=sorted((ROOT/'Sources').glob('*.swift'))
sdk=Path(run(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],capture_output=True,text=True).stdout.strip())
native_main=B/'NativeMain.o'
run(['/usr/bin/clang','-fobjc-arc','-g','-arch','arm64','-mmacosx-version-min=14.0','-isysroot',sdk,'-c',ROOT/'Sources/NativeMain.m','-o',native_main])
run(['/usr/bin/swiftc','-swift-version','5','-O','-g','-target','arm64-apple-macosx14.0','-sdk',sdk,'-F',B,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',*sources,native_main,'-o',mac/'Dianyu'])
# Keep matching private symbols for future native crash reports, outside the app.
symbols=B/('Dianyu-'+args.version+'-'+args.build+'.dSYM')
# swiftc runs dsymutil while its temporary objects still exist. Preserve that
# complete bundle; re-running dsymutil later loses source/line information.
generated=mac/'Dianyu.dSYM'
if not generated.is_dir():raise SystemExit('Matching native debug symbols missing.')
if symbols.exists():shutil.rmtree(symbols)
shutil.move(generated,symbols)
run(['/usr/bin/strip','-S',mac/'Dianyu'])
run(['/usr/bin/swiftc','-swift-version','5','-O','-target','arm64-apple-macosx14.0','-sdk',sdk,ROOT/'Sources/Domain.swift',ROOT/'Sources/Resources.swift',ROOT/'Sources/RecordingMute.swift',ROOT/'Tools/AudioRestoreGuard.swift','-o',resources/'AudioRestoreGuard'])
print('Native application compiled.')
if args.compile_only:sys.exit(0)
run(['/usr/bin/swift',ROOT/'Tools/Icon.swift',B/'Brand.iconset',ROOT/'Resources/BrandLogo.png'])
config=json.loads(profile.read_text())
info={'CFBundleIdentifier':'im.muse.dianyu','CFBundleName':'咸鱼说','CFBundleDisplayName':'咸鱼说','CFBundleExecutable':'Dianyu','CFBundlePackageType':'APPL','CFBundleIconFile':'AppIcon','CFBundleShortVersionString':args.version,'CFBundleVersion':args.build,'LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'LSUIElement':True,'NSMicrophoneUsageDescription':'咸鱼说使用麦克风录制你主动开始的听写。识别、整理和翻译全部在本机完成。','NSHumanReadableCopyright':'Copyright © 2026 Dianyu','SUEnableAutomaticChecks':False,'SUAllowsAutomaticUpdates':False,'SUEnableSystemProfiling':False,'SUPublicEDKey':config['update_public_key'],'NSAppTransportSecurity':{'NSAllowsArbitraryLoads':False}}
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
for src,dst in [(B/'Runtime',resources/'Runtime'),(B/'PythonExtras',resources/'PythonExtras'),(B/'Sparkle.framework',frameworks/'Sparkle.framework')]:
    if not dst.exists():run(['/bin/cp','-cR',src,dst])
for item in (ROOT/'Resources').iterdir():
    if item.is_file():shutil.copy2(item,resources/item.name)
if (resources/'Engine').exists():shutil.rmtree(resources/'Engine')
shutil.copytree(ROOT/'Engine',resources/'Engine',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
for tree in [resources/'Runtime',resources/'PythonExtras']:
    for cache in tree.rglob('__pycache__'):
        if cache.is_dir():shutil.rmtree(cache)
entitlements=B/'entitlements.plist';entitlements.write_bytes(plistlib.dumps({'com.apple.security.device.audio-input':True,'com.apple.security.cs.disable-library-validation':True}))
run(['/usr/bin/security','unlock-keychain','-p',config['password'],config['keychain']],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
def sign(path):
    run(['/usr/bin/codesign','--force','--sign',config['fingerprint'],'--keychain',config['keychain'],'--options','runtime','--timestamp=none','--entitlements',entitlements,path],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
marker=B/'runtime-signed-identity'
if not marker.exists() or marker.read_text()!=config['fingerprint']:
    magic={bytes.fromhex(v)for v in ['cffaedfe','cefaedfe','cafebabe','bebafeca']}
    native=[]
    for root in [resources/'Runtime',resources/'PythonExtras']:
        for p in root.rglob('*'):
            if p.is_file() and not p.is_symlink():
                with p.open('rb')as f:
                    if f.read(4)in magic:native.append(p)
    for p in sorted(native,key=lambda x:len(x.parts),reverse=True):sign(p)
    marker.write_text(config['fingerprint']);print('Signed',len(native),'embedded runtime binaries with the fixed identity.')
# Preserve official Sparkle helper signatures; sign the containing framework for this host.
sign(resources/'AudioRestoreGuard');sign(frameworks/'Sparkle.framework');sign(app)
run(['/usr/bin/codesign','--verify','--deep','--strict',app])
description=run(['/usr/bin/codesign','-d','-r-',app],capture_output=True,text=True)
assert config['fingerprint'].lower()in(description.stdout+description.stderr).lower(),'Stable identity requirement mismatch'
print('Built and verified fixed local signature:',app)
