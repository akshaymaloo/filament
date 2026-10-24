import XCTest

/// Keeps the app, the Quick Look extensions and project.yml consistent. These
/// targets aren't built by SwiftPM, so they are checked from their sources.
final class BundleConfigurationTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any], path)
    }

    private func supportedTypes(_ path: String) throws -> [String] {
        let info = try plist(path)
        let ext = try XCTUnwrap(info["NSExtension"] as? [String: Any])
        let attrs = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        return try XCTUnwrap(attrs["QLSupportedContentTypes"] as? [String])
    }

    private func appTypes() throws -> Set<String> {
        let info = try plist("App/Filament/Info.plist")
        var types = Set<String>()
        for key in ["UTImportedTypeDeclarations", "UTExportedTypeDeclarations"] {
            for decl in info[key] as? [[String: Any]] ?? [] {
                if let id = decl["UTTypeIdentifier"] as? String { types.insert(id) }
            }
        }
        for doc in info["CFBundleDocumentTypes"] as? [[String: Any]] ?? [] {
            types.formUnion(doc["LSItemContentTypes"] as? [String] ?? [])
        }
        return types
    }

    private let extensionPlists = [
        "Extensions/PreviewExtension/Info.plist",
        "Extensions/ThumbnailExtension/Info.plist",
    ]

    func testExtensionsSupportExactlyTheAppsTypes() throws {
        let app = try appTypes()
        XCTAssertFalse(app.isEmpty)
        for path in extensionPlists {
            let types = try supportedTypes(path)
            XCTAssertEqual(types.count, Set(types).count, "duplicate types in \(path)")
            XCTAssertEqual(Set(types).subtracting(app), [], "\(path) lists types the app doesn’t know")
            XCTAssertEqual(app.subtracting(types), [], "\(path) is missing types the app declares")
        }
    }

    func testExtensionPointIdentifiers() throws {
        let expected = [
            "Extensions/PreviewExtension/Info.plist": "com.apple.quicklook.preview",
            "Extensions/ThumbnailExtension/Info.plist": "com.apple.quicklook.thumbnail",
        ]
        for (path, point) in expected {
            let ext = try XCTUnwrap(try plist(path)["NSExtension"] as? [String: Any])
            XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, point, path)
        }
    }

    // MARK: project.yml

    private func projectLines() throws -> [String] {
        try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8).components(separatedBy: "\n")
    }

    /// All values of `key: value` lines, with quotes stripped.
    private func values(of key: String, in lines: [String]) -> [String] {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key + ":") else { return nil }
            return trimmed.dropFirst(key.count + 1)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
    }

    func testExtensionBundleIdentifiersArePrefixedByAppIdentifier() throws {
        let ids = values(of: "PRODUCT_BUNDLE_IDENTIFIER", in: try projectLines())
        XCTAssertEqual(ids.count, 3)
        let app = try XCTUnwrap(ids.min { $0.count < $1.count })
        let extensions = ids.filter { $0 != app }
        XCTAssertEqual(extensions.count, 2)
        for id in extensions { XCTAssertTrue(id.hasPrefix(app + "."), id) }
    }

    func testVersionsAreDeclaredOnceAndWellFormed() throws {
        let lines = try projectLines()
        let marketing = values(of: "MARKETING_VERSION", in: lines)
        let build = values(of: "CURRENT_PROJECT_VERSION", in: lines)
        XCTAssertEqual(Set(marketing).count, 1)
        XCTAssertEqual(Set(build).count, 1)
        XCTAssertNotNil(marketing.first?.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression))
        XCTAssertNotNil(build.first.flatMap(Int.init))
    }

    func testPlistsUseVersionBuildSettings() throws {
        for path in extensionPlists + ["App/Filament/Info.plist"] {
            let info = try plist(path)
            XCTAssertEqual(info["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)", path)
            XCTAssertEqual(info["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)", path)
        }
    }
}
