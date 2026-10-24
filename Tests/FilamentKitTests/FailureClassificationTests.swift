import XCTest
@testable import FilamentKit
import FilamentTestSupport

/// Writes real broken files to disk and checks the whole path from
/// `ModelLoader` to user-facing copy yields a specific (non-generic) message.
final class FailureClassificationTests: XCTestCase {
    private let generic = "The file couldn’t be read."

    private func classify(_ name: String, _ contents: Data, file: StaticString = #filePath, line: UInt = #line) throws -> LoadFailureMessage {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FilamentKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        let message: LoadFailureMessage
        do {
            let document = try ModelLoader().load(url: url)
            guard document.hasNoGeometry else {
                XCTFail("expected a failure or empty model for \(name)", file: file, line: line)
                return .emptyModel()
            }
            message = .emptyModel(fileName: name, context: .open)
        } catch {
            message = LoadFailureMessage(error: error, fileName: name, context: .open)
        }
        XCTAssertNotEqual(message.detail, generic, name, file: file, line: line)
        XCTAssertTrue(message.title.contains("“\(name)”"), file: file, line: line)
        return message
    }

    func testCorruptZipNamed3MF() throws {
        let message = try classify("broken.3mf", Data("this is not a zip".utf8))
        XCTAssertEqual(message.detail, "The file may be damaged, or it isn’t a valid 3MF file.")
    }

    func testValidZipWithoutModelPart() throws {
        var writer = ZipWriter()
        writer.addEntry(path: "readme.txt", data: Data("hi".utf8), method: .store)
        let message = try classify("nomodel.3mf", writer.finalize())
        XCTAssertEqual(message.detail, "The file doesn’t contain a 3D model.")
    }

    func testEmptySTL() throws {
        let message = try classify("empty.stl", Data())
        XCTAssertFalse(message.detail.isEmpty)
    }

    func testTruncatedBinarySTL() throws {
        let cube = FilamentFixtureFactory.stlBinaryCube()
        let message = try classify("cut.stl", cube.prefix(cube.count - 20))
        XCTAssertFalse(message.detail.isEmpty)
    }

    func testOBJWithVerticesButNoFaces() throws {
        let message = try classify("points.obj", Data("v 0 0 0\nv 1 0 0\nv 0 1 0\n".utf8))
        XCTAssertEqual(message.detail, "This file doesn’t contain any 3D geometry.")
    }

    func testPLYWithBadHeader() throws {
        let message = try classify("bad.ply", Data("ply\nformat bogus 1.0\nend_header\n".utf8))
        XCTAssertEqual(message.detail, "The model data in this file couldn’t be read.")
    }

    func testUnknownExtensionWithGarbage() throws {
        _ = try classify("mystery.xyz", Data("garbage".utf8))
    }
}
