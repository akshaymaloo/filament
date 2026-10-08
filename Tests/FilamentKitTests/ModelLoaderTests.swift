import XCTest
@testable import FilamentKit
import FilamentTestSupport

/// Exercises `ModelLoader`'s dispatch/sniffing paths not already covered by
/// `MeshFormatsTests` (basic per-format happy paths) or `RobustnessTests`
/// (adversarial STL/OBJ sniffing edge cases).
final class ModelLoaderTests: XCTestCase {

    private func withTempFile<T>(named name: String, contents: Data, _ body: (URL) throws -> T) throws -> T {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FilamentKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent(name)
        try contents.write(to: fileURL)
        return try body(fileURL)
    }

    // MARK: - load(data:format:name:)

    func testLoadDataThreeMFFormatDelegatesToThreeMFLoader() throws {
        let doc = try ModelLoader().load(data: FilamentFixtureFactory.minimalCube(deflate: true), format: .threeMF, name: "ignored")
        XCTAssertEqual(doc.unit, .millimeter)
        XCTAssertEqual(doc.plates.count, 1)
        XCTAssertEqual(doc.plates[0].mesh.triangleCount, 12)
        // For .threeMF the `name` argument is ignored; the document supplies
        // its own plate name (the implicit single plate is always "Plate 1").
        XCTAssertEqual(doc.plates[0].name, "Plate 1")
    }

    func testLoadDataParseMeshFalseProducesEmptyMeshAndUsesGivenName() throws {
        var options = ThreeMFLoader.Options.default
        options.parseMesh = false
        let loader = ModelLoader(options: options)

        for format: ModelFormat in [.stl, .obj, .ply] {
            let data: Data
            switch format {
            case .stl: data = FilamentFixtureFactory.stlBinaryCube()
            case .obj: data = FilamentFixtureFactory.objCube()
            case .ply: data = FilamentFixtureFactory.plyASCIICube()
            case .threeMF: XCTFail("unreachable"); continue
            }
            let doc = try loader.load(data: data, format: format, name: "my-model")
            XCTAssertEqual(doc.unit, .millimeter)
            XCTAssertEqual(doc.plates.count, 1)
            let plate = doc.plates[0]
            XCTAssertEqual(plate.id, 1)
            XCTAssertEqual(plate.name, "my-model")
            XCTAssertNil(plate.thumbnail)
            XCTAssertNil(plate.stats)
            XCTAssertTrue(plate.mesh.isEmpty, "\(format) with parseMesh=false should produce an empty mesh")
            XCTAssertNil(doc.packageThumbnail)
        }
    }

    // MARK: - extractPrimaryThumbnail(url:)

    func testExtractPrimaryThumbnailURLReturnsDataFor3MF() throws {
        try withTempFile(named: "project.3mf", contents: FilamentFixtureFactory.bambuTwoPlates()) { url in
            let thumbnail = try ModelLoader().extractPrimaryThumbnail(url: url)
            XCTAssertNotNil(thumbnail)
        }
    }

    func testExtractPrimaryThumbnailURLNilForMeshFormats() throws {
        try withTempFile(named: "cube.stl", contents: FilamentFixtureFactory.stlBinaryCube()) { url in
            XCTAssertNil(try ModelLoader().extractPrimaryThumbnail(url: url))
        }
    }

    // MARK: - Content sniffing (missing/unrecognized extension)

    func testSniffFormatDetectsThreeMFBySignature() throws {
        try withTempFile(named: "no-extension", contents: FilamentFixtureFactory.minimalCube(deflate: true)) { url in
            let doc = try ModelLoader().load(url: url)
            XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
        }
    }

    func testSniffFormatDetectsPLYByMagicHeader() throws {
        try withTempFile(named: "no-extension", contents: FilamentFixtureFactory.plyASCIICube()) { url in
            let doc = try ModelLoader().load(url: url)
            XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
        }
    }

    func testSniffFormatDetectsOBJByVertexAndFaceLines() throws {
        try withTempFile(named: "no-extension", contents: FilamentFixtureFactory.objCube()) { url in
            let doc = try ModelLoader().load(url: url)
            XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
        }
    }

    func testSniffFormatDetectsSTLByHeuristic() throws {
        try withTempFile(named: "no-extension", contents: FilamentFixtureFactory.stlBinaryCube()) { url in
            let doc = try ModelLoader().load(url: url)
            XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
        }
    }

    func testSniffFormatThrowsMalformedMeshForUnrecognizedContent() throws {
        try withTempFile(named: "no-extension", contents: Data(repeating: 0x00, count: 16)) { url in
            XCTAssertThrowsError(try ModelLoader().load(url: url)) { error in
                guard case FilamentError.malformedMesh = error else {
                    return XCTFail("Expected malformedMesh, got \(error)")
                }
            }
        }
    }

    func testUnrecognizedFileExtensionFallsBackToSniffing() throws {
        // A real STL payload under a nonsense extension: `ModelFormat(fileExtension:)`
        // returns nil, so the loader must fall back to content sniffing.
        try withTempFile(named: "cube.xyz", contents: FilamentFixtureFactory.stlBinaryCube()) { url in
            let doc = try ModelLoader().load(url: url)
            XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
        }
    }
}
