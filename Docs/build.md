# 构建与测试

## 准备依赖

需要 Apple Silicon Mac、macOS 14 或更新版本和 Xcode 命令行工具。编译时使用包含当前 UI API 的 macOS SDK。模型权重与 App 运行环境独立。

1. 准备可搬移的 arm64 CPython 3.12，目录中应有 `bin/python3`。可从 [Python Build Standalone](https://github.com/astral-sh/python-build-standalone/releases) 选择 `aarch64-apple-darwin` 的 `install_only` 包。
2. 从 [Sparkle 2.10.0 官方发布页](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) 下载并解压，找到 `Sparkle.framework`。
3. 在仓库根目录执行以下命令，将示例路径替换成实际路径。

```sh
python3 Tools/prepare.py --runtime /path/to/python --sparkle /path/to/Sparkle.framework
build/Runtime/bin/python3 -m ensurepip
build/Runtime/bin/python3 -m pip install --target build/PythonExtras -r Tools/runtime-requirements.txt
```

如果已经有依赖齐全的 Python 包目录，可以用 `--python-extras /path/to/site-packages` 暂存。

## 编译与运行

```sh
python3 Tools/build.py --compile-only --version 0.1.46 --build 90
```

首次完整构建在独立开发环境中执行 `python3 Tools/build.py --initialize-signing --version 0.1.46 --build 90`。后续完整构建沿用同一开发签名，省略 `--initialize-signing`。签名资料存放在本地 `private-signing/`。完整应用生成于 `build/咸鱼说.app`。构建器会阻止误为已有生产安装生成新的本地身份。开发签名与对外分发所需的签名、公证分别管理。

启动完整应用后，在首次引导中授权麦克风和辅助功能，并在「模型」中下载所需权重。只有识别模型是基础听写所必需的。

## 回归检查

```sh
PYTHONPATH="$PWD/build/PythonExtras" build/Runtime/bin/python3 -B -m unittest discover -s Tests -p 'test_*.py'
python3 Tools/test_delivery.py
```

`Tests/` 中还有针对自有设备、安装包、历史录音与私有基准样本的独立验收脚本。这类脚本需要另行准备本地素材，不属于上述可公开复现的单元测试。

每次应用变更先跑相关回归，再更新 [更新记录](../CHANGELOG.md)，提交公开文件并推送到 `origin/main`。安装包、模型和本地测试材料不进入 Git。
