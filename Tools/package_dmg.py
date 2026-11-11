"""Package the installed, signed application as a drag-to-Applications DMG."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(*args, capture=False):
    return subprocess.run(list(map(str, args)), check=True, capture_output=capture, text=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app = Path('/Applications/咸鱼说.app')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    image = output/f'Xianyushuo-{version}-arm64.dmg'
    if image.exists():
        raise SystemExit('The destination DMG already exists. Choose a new output directory.')
    with tempfile.TemporaryDirectory(prefix='xianyushuo-dmg-') as temp:
        staging = Path(temp)/'contents'
        staging.mkdir()
        run('/usr/bin/ditto', app, staging/app.name)
        (staging/'Applications').symlink_to('/Applications')
        instructions = (
            f'咸鱼说 {version} · Apple Silicon · macOS 14+\n\n'
            '将“咸鱼说.app”拖到 Applications 文件夹，再从“应用程序”打开。\n'
            '模型按需下载，安装包不包含模型、个人词表、历史或 API Key。\n'
            '首次使用请在应用引导中配置麦克风、辅助功能和所需的本地模型。\n'
            '默认使用本地整理。选用 DeepSeek 时，请自行配置 API Key，'
            '待整理的文字会发送给 DeepSeek，可能产生 API 费用。\n'
            '此版本使用固定本地开发签名，尚未经过 Apple Developer ID 公证。\n'
            '如 macOS 阻止首次打开，请在确认来源后前往系统设置 → 隐私与安全性查看提示。\n\n'
            'Drag 咸鱼说.app to Applications, then open it from Applications.\n'
            'Models download on demand. Your API key, vocabulary and history are stored separately.\n'
            'DeepSeek cleanup is optional and sends transcript text to DeepSeek, with API charges.\n'
            'This build has a fixed local development signature and is not Apple-notarized.\n'
        )
        (staging/'安装说明 Installation.txt').write_text(instructions)
        run('/usr/bin/hdiutil', 'create', '-volname', f'咸鱼说 {version}', '-srcfolder', staging,
            '-fs', 'HFS+', '-format', 'UDZO', image)
    # Preserve the dedicated local signing identity used by the application.
    config = json.loads((ROOT/'private-signing/profile.json').read_text())
    result = subprocess.run(
        ['/usr/bin/codesign', '--force', '--sign', config['fingerprint'], '--keychain',
         config['keychain'], '--timestamp=none', str(image)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit('DMG signing failed. Signing arguments omitted.')
    run('/usr/bin/codesign', '--verify', '--strict', image)
    run('/usr/bin/hdiutil', 'verify', image)
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    (output/'SHA256SUMS.txt').write_text(f'{digest}  {image.name}\n')
    metadata = dict(
        version=version, build=info['CFBundleVersion'], bundle_id=info['CFBundleIdentifier'],
        file=image.name, bytes=image.stat().st_size, sha256=digest,
        signing='fixed local development signature', apple_notarized=False, models_included=False,
    )
    (output/'release.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == '__main__':
    main()
