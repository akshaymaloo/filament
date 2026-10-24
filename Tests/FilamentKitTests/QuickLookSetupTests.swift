import XCTest
@testable import FilamentKit

final class QuickLookSetupTests: XCTestCase {
    private let me = "com.filament3d.Filament"
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func all(_ id: String?) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: QuickLookSetup.supportedExtensions.map { ($0, id) })
    }

    func testAllFilament() {
        let d = all(me)
        XCTAssertEqual(QuickLookSetup.extensionsNeedingChange(defaults: d, ownBundleID: me), [])
        XCTAssertEqual(QuickLookSetup.statusText(defaults: d, ownBundleID: me),
                       "Filament opens 3MF, STL, OBJ, and PLY files.")
    }

    func testNoneFilamentGroupsByApp() {
        let d = all("com.apple.dt.Xcode")
        XCTAssertEqual(QuickLookSetup.extensionsNeedingChange(defaults: d, ownBundleID: me),
                       ["3mf", "stl", "obj", "ply"])
        XCTAssertEqual(
            QuickLookSetup.statusText(defaults: d, ownBundleID: me, appNames: ["com.apple.dt.Xcode": "Xcode"]),
            "3MF, STL, OBJ, and PLY files open in Xcode.")
    }

    func testMixed() {
        var d = all(me)
        d["stl"] = .some("com.apple.dt.Xcode")
        d["obj"] = .some("com.apple.dt.Xcode")
        d["ply"] = .some("com.other")
        let names = ["com.apple.dt.Xcode": "Xcode", "com.other": "Blender"]
        XCTAssertEqual(QuickLookSetup.extensionsNeedingChange(defaults: d, ownBundleID: me), ["stl", "obj", "ply"])
        XCTAssertEqual(QuickLookSetup.statusText(defaults: d, ownBundleID: me, appNames: names),
                       "STL and OBJ files open in Xcode. PLY file opens in Blender.")
    }

    func testNilAndUnknownApps() {
        var d = all(me)
        d["stl"] = .some(nil)
        d["obj"] = nil
        d["ply"] = .some("com.unknown")
        XCTAssertEqual(QuickLookSetup.extensionsNeedingChange(defaults: d, ownBundleID: me), ["stl", "obj", "ply"])
        XCTAssertEqual(QuickLookSetup.statusText(defaults: d, ownBundleID: me),
                       "STL and OBJ files have no default app. PLY file opens in another app.")
    }

    func testInstallScriptMatchesCommands() throws {
        let script = try String(contentsOf: root.appendingPathComponent("install.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("HYDRA_ID=\"\(QuickLookSetup.hydraExtensionID)\""))
        XCTAssertTrue(script.contains("pluginkit -e ignore -i \"$HYDRA_ID\""))
        XCTAssertTrue(script.contains("pluginkit -e default -i \"$HYDRA_ID\""))
        XCTAssertTrue(QuickLookSetup.preferFilamentCommand.hasPrefix("pluginkit -e ignore -i \(QuickLookSetup.hydraExtensionID)"))
        XCTAssertTrue(QuickLookSetup.restoreAppleCommand.hasPrefix("pluginkit -e default -i \(QuickLookSetup.hydraExtensionID)"))
    }
}
