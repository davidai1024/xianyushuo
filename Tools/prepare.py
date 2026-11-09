"""Stage supplied build dependencies. No access to app data or model stores."""
from argparse import ArgumentParser
from pathlib import Path
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def stage(source, destination):
    if destination.exists():
        raise SystemExit(f"Dependency already staged: {destination}")
    subprocess.run(["/bin/cp", "-cR", str(source), str(destination)], check=True)


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path, required=True, help="Relocatable arm64 CPython 3.12 directory")
    parser.add_argument("--sparkle", type=Path, required=True, help="Sparkle.framework from the official release")
    parser.add_argument("--python-extras", type=Path, help="Optional prepared Python dependency directory")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise SystemExit("Run this on an Apple Silicon Mac.")
    runtime = args.runtime.resolve()
    sparkle = args.sparkle.resolve()
    extras = args.python_extras.resolve() if args.python_extras else None
    if not (runtime / "bin/python3").is_file():
        raise SystemExit("The runtime directory must contain bin/python3.")
    subprocess.run([str(runtime / "bin/python3"), "-c",
                    "import platform, sys; assert platform.machine() == 'arm64' and sys.version_info[:2] == (3, 12)"],
                   check=True)
    if sparkle.name != "Sparkle.framework" or not sparkle.is_dir():
        raise SystemExit("The Sparkle argument must point to Sparkle.framework.")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(sparkle)], check=True)
    if extras is not None and not extras.is_dir():
        raise SystemExit("The Python dependency directory does not exist.")
    build = ROOT / "build"
    for name in ("Runtime", "PythonExtras", "Sparkle.framework"):
        if (build / name).exists():
            raise SystemExit(f"Dependency already staged: {build / name}")
    build.mkdir(exist_ok=True)
    stage(runtime, build / "Runtime")
    stage(sparkle, build / "Sparkle.framework")
    if extras is None:
        (build / "PythonExtras").mkdir()
    else:
        stage(extras, build / "PythonExtras")


if __name__ == "__main__":
    main()
