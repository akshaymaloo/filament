import XCTest
@testable import ThreeMFKit

final class MeshFormatsTests: XCTestCase {

    private func assertCubeDocument(_ doc: ThreeMFDocument, expectedName: String) throws {
        XCTAssertEqual(doc.unit, .millimeter)
        XCTAssertEqual(doc.plates.count, 1)
        let plate = try XCTUnwrap(doc.plates.first)
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        XCTAssertEqual(plate.name, expectedName)

        let bbox = try XCTUnwrap(plate.mesh.boundingBox)
        XCTAssertEqual(bbox.min, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(bbox.max, SIMD3<Float>(20, 20, 20))
    }

    func testSTLBinaryCube() throws {
        let data = ThreeMFFixtureFactory.stlBinaryCube()
        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)

        let doc = try ModelLoader().load(data: data, format: .stl, name: "stl-binary-cube")
        try assertCubeDocument(doc, expectedName: "stl-binary-cube")
    }

    func testSTLASCIICube() throws {
        let data = ThreeMFFixtureFactory.stlASCIICube()
        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)

        let doc = try ModelLoader().load(data: data, format: .stl, name: "stl-ascii-cube")
        try assertCubeDocument(doc, expectedName: "stl-ascii-cube")
    }

    func testOBJCube() throws {
        let data = ThreeMFFixtureFactory.objCube()
        let mesh = try OBJParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)

        let doc = try ModelLoader().load(data: data, format: .obj, name: "obj-cube")
        try assertCubeDocument(doc, expectedName: "obj-cube")
    }

    func testPLYASCIICube() throws {
        let data = ThreeMFFixtureFactory.plyASCIICube()
        let mesh = try PLYParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)

        let doc = try ModelLoader().load(data: data, format: .ply, name: "ply-ascii-cube")
        try assertCubeDocument(doc, expectedName: "ply-ascii-cube")
    }

    func testPLYBinaryLittleEndianCube() throws {
        let data = ThreeMFFixtureFactory.plyBinaryLECube()
        let mesh = try PLYParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)

        let doc = try ModelLoader().load(data: data, format: .ply, name: "ply-binary-le-cube")
        try assertCubeDocument(doc, expectedName: "ply-binary-le-cube")
    }

    func testPLYBinaryBigEndianCube() throws {
        let data = ThreeMFFixtureFactory.plyBinaryBECube()
        let mesh = try PLYParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)

        let doc = try ModelLoader().load(data: data, format: .ply, name: "ply-binary-be-cube")
        try assertCubeDocument(doc, expectedName: "ply-binary-be-cube")
    }

    func testModelFormatFileExtensionLookup() {
        XCTAssertEqual(ModelFormat(fileExtension: "STL"), .stl)
        XCTAssertEqual(ModelFormat(fileExtension: ".obj"), .obj)
        XCTAssertEqual(ModelFormat(fileExtension: "PLY"), .ply)
        XCTAssertEqual(ModelFormat(fileExtension: "3mf"), .threeMF)
        XCTAssertNil(ModelFormat(fileExtension: "xyz"))
        XCTAssertEqual(ModelFormat.supportedExtensions, ["3mf", "stl", "obj", "ply"])
    }

    func testModelLoaderURLDispatchByExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ThreeMFKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("my-cube.stl")
        try ThreeMFFixtureFactory.stlBinaryCube().write(to: fileURL)

        let doc = try ModelLoader().load(url: fileURL)
        try assertCubeDocument(doc, expectedName: "my-cube")
    }

    func testModelLoaderThumbnailIsNilForMeshFormats() throws {
        XCTAssertNil(try ModelLoader().load(data: ThreeMFFixtureFactory.stlBinaryCube(), format: .stl, name: "cube").primaryThumbnail)
    }

    func testMalformedSTLThrows() {
        XCTAssertThrowsError(try STLParser.parse(data: Data("not an stl file".utf8)))
    }

    func testMalformedOBJThrows() {
        // Face references vertex index 99, but only 1 vertex is defined.
        let data = Data("v 0 0 0\nf 1 2 3\n".utf8)
        XCTAssertThrowsError(try OBJParser.parse(data: data))
    }

    func testMalformedPLYThrows() {
        XCTAssertThrowsError(try PLYParser.parse(data: Data("not a ply file".utf8)))
    }
}
