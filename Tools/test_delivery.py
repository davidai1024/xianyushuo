"""Focused-input evidence and deferred one-shot delivery; no UI, mic or user data."""
from pathlib import Path
import subprocess, tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="DianyuDelivery-") as directory:
    executable = Path(directory) / "delivery-tests"
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    subprocess.run(["swiftc", "-swift-version", "5", "-O", "-g", "-sanitize=address", "-sdk", sdk,
                    str(root / "Sources/Domain.swift"), str(root / "Sources/Resources.swift"), str(root / "Sources/Delivery.swift"),
                    str(root / "Tests/DeliveryEvidenceTests.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
