"""Create reviewable local artifacts. Never uploads, publishes, or includes keys."""
from pathlib import Path
import subprocess,json,hashlib,zipfile,argparse,plistlib,html
R=Path(__file__).resolve().parents[1];P=argparse.ArgumentParser();P.add_argument('--output',type=Path,required=True);P.add_argument('--url');args=P.parse_args()
out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
app=Path('/Applications/咸鱼说.app')
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());version=info['CFBundleShortVersionString']
archive=out/('咸鱼说-'+version+'-AppleSilicon.zip')
subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(app),str(archive)],check=True)
profile=json.loads((R/'private-signing/profile.json').read_text())
signature=subprocess.run(['/usr/bin/swift',str(R/'Tools/SignUpdate.swift'),str(R/'private-signing/update-ed25519.key'),str(archive)],check=True,capture_output=True,text=True).stdout.strip()
record=dict(version=version,build=info['CFBundleVersion'],bundle_id=info['CFBundleIdentifier'],archive=archive.name,bytes=archive.stat().st_size,sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),ed25519_signature=signature,update_public_key=profile['update_public_key'],signing='fixed local self-signed; not Apple-notarized',models_included=False)
(out/'咸鱼说安装包校验.json').write_text(json.dumps(record,ensure_ascii=False,indent=2))
if args.url:
    from urllib.parse import urlsplit
    url=urlsplit(args.url)
    if url.scheme!='https' or not url.netloc:raise SystemExit('Public download URL must use HTTPS')
    item=f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>咸鱼说更新</title><item><title>{html.escape(version)}</title><sparkle:version>{html.escape(info['CFBundleVersion'])}</sparkle:version><sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url="{html.escape(args.url,quote=True)}" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>'''
    (out/'appcast.xml').write_text(item)
source=out/'咸鱼说源码与测试.zip'
with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED)as z:
    for folder in ['Sources','Engine','Tools','Tests','Resources','Docs']:
        for file in (R/folder).rglob('*'):
            if file.is_file() and '__pycache__'not in file.parts and file.suffix!='.pyc':z.write(file,'Dianyu/'+str(file.relative_to(R)))
    for name in ['AGENTS.md','README.txt','.gitignore']:
        z.write(R/name,'Dianyu/'+name)
assert not any('private-signing'in x or 'human-private'in x or 'vocabulary.json'in x for x in zipfile.ZipFile(source).namelist())
print('Local application archive and sanitized source archive created; nothing published.')
