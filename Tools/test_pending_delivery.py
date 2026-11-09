"""Exercise production deferred-delivery lifecycle with isolated fake OS edges."""
from pathlib import Path
import subprocess, tempfile, shutil

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="DianyuPending-") as directory:
    temporary = Path(directory)
    sources = temporary / "Sources"
    shutil.copytree(root / "Sources", sources)
    path = sources / "AppState.swift"
    text = path.read_text().replace("    func startServices(){", "    func startServices(){\n        return\n", 1)
    marker = "    private var pendingDelivery:Task<Void,Never>?"
    assert marker in text
    text = text.replace(marker, marker + """
    var testFocusAvailable=false
    var testFocusText=""
    var testClipboardVersion=42
    var testDeliveryCalls=0
""", 1)
    start = text.index("    private func awaitInput(id:UUID){")
    end = text.index("    func retry(", start)
    body = text[start:end]
    assert body.count("PasteTarget.capture()") == 1 and body.count("await Delivery.deliver(") == 1
    body = body.replace("NSPasteboard.general.changeCount", "self.testClipboardVersion")
    body = body.replace("let destination=PasteTarget.capture()", "let destination=self.testDestination()")
    body = body.replace("await Delivery.deliver(", "await self.testDeliver(")
    text = text[:start] + body + text[end:]
    text += """
extension AppState {
    func testSeedPending()throws->UUID {
        var record=SessionRecord();record.source="test";record.status="completed"
        record.output="测试 C theft thief。";record.delivery="waiting"
        record.metadata="{\\\"delivery\\\":{\\\"reason\\\":\\\"input_not_focused\\\"}}"
        try store.update(record);active=nil;latest=record.id;phase="result"
        deliveryState="clipboard";awaitInput(id:record.id);return record.id
    }
    func testStopPending(){stopPendingDelivery()}
    func testResetSleep(){sleeping=false}
    func testDestination()->PasteTarget {
        PasteTarget(pid:12345,bundleID:"fixture",element:testFocusAvailable ? AXUIElementCreateApplication(12345):nil,
            window:nil,role:"AXTextArea",focusedRole:"AXTextArea",focusedOwner:12345,identifier:"fixture",
            geometry:nil,text:testFocusText,selection:CFRange(location:(testFocusText as NSString).length,length:0),clipboardVersion:testClipboardVersion)
    }
    func testDeliver(_ text:String,target:PasteTarget?,preferences:Preferences,stillCurrent:()->Bool)async->DeliveryReceipt {
        precondition(stillCurrent());precondition(store.sessions.contains{$0.output==text && $0.status=="completed"})
        testDeliveryCalls+=1
        return DeliveryReceipt(state:"verified",message:"verified fixture delivery",audit:["method":"fixture","verified":true])
    }
}
"""
    path.write_text(text)
    path = sources / "Hotkeys.swift"
    text = path.read_text()
    path.write_text(text.replace("    init(){", "    init(){\n        suppress=true;return\n", 1))
    executable = temporary / "pending-tests"
    sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    subprocess.run(["swiftc", "-swift-version", "5", "-O", "-g", "-sanitize=address", "-sdk", sdk,
                    "-F", str(root / "build"), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(root / "build"),
                    *map(str, sorted(sources.glob("*.swift"))), str(root / "Tests/PendingDeliveryTests.swift"), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
