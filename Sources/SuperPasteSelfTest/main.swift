import AppKit
import SuperPasteCore

// Headless logic checks (the Command Line Tools have no XCTest). Run: swift run SuperPasteSelfTest
var failures = 0
func check(_ cond: @autoclosure () -> Bool, _ msg: String, file: String = #fileID, line: Int = #line) {
    if !cond() { failures += 1; print("✗ \(file):\(line) \(msg)") }
}
enum SelfTest { nonisolated(unsafe) static var cases: [(String, () -> Void)] = [] }

// Files and settings live in throwaway places, never the real Application Support folder or preferences.
SuperPastePaths.base = FileManager.default.temporaryDirectory.appendingPathComponent("superpaste-selftest-\(UUID().uuidString)")
let defaultsSuite = "superpaste-selftest-\(UUID().uuidString)"
Defaults.store = UserDefaults(suiteName: defaultsSuite)!

// Each module owns Sources/SuperPasteSelfTest/<Module>Tests.swift and its register function; EndToEndTests.swift
// runs the modules together.
registerCoreTests()
registerClipStoreTests()
registerClipboardKitTests()
registerStripKitTests()
registerSettingsKitTests()
registerSyncKitTests()
registerMCPKitTests()
registerUpdateKitTests()
registerEndToEndTests()

for (name, run) in SelfTest.cases {
    let before = failures; run()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}
try? FileManager.default.removeItem(at: SuperPastePaths.base)
UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
print(failures == 0 ? "All self-tests passed." : "\(failures) failure(s).")
exit(failures == 0 ? 0 : 1)
