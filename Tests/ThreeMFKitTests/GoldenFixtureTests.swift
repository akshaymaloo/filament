import XCTest
@testable import ThreeMFKit

/// A "golden" regression corpus: every public fixture `ThreeMFFixtureFactory`
/// produces (plus a few small hand-built OBJ/PLY/STL inputs), loaded through
/// the same public `ModelLoader`/`ThreeMFLoader` API real callers use, with
/// exact expected results pinned (triangle/vertex counts, bounding boxes,
/// palette/colors, plate names/stats, thumbnail presence). Any behavior
/// change in parsing/resolution/coloring should turn into a precise failing
/// assertion here, rather than a silent drift.
final class GoldenFixtureTests: XCTestCase {
    private let bboxAccuracy: Float = 1e-4

    private func assertBoundingBox(
        _ mesh: TriangleMesh,
        min expectedMin: SIMD3<Float>,
        max expectedMax: SIMD3<Float>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let box = try XCTUnwrap(mesh.boundingBox, file: file, line: line)
        XCTAssertEqual(box.min.x, expectedMin.x, accuracy: bboxAccuracy, file: file, line: line)
        XCTAssertEqual(box.min.y, expectedMin.y, accuracy: bboxAccuracy, file: file, line: line)
        XCTAssertEqual(box.min.z, expectedMin.z, accuracy: bboxAccuracy, file: file, line: line)
        XCTAssertEqual(box.max.x, expectedMax.x, accuracy: bboxAccuracy, file: file, line: line)
        XCTAssertEqual(box.max.y, expectedMax.y, accuracy: bboxAccuracy, file: file, line: line)
        XCTAssertEqual(box.max.z, expectedMax.z, accuracy: bboxAccuracy, file: file, line: line)
    }

    // MARK: - Plain single-cube 3MF fixtures

    func testMinimalCubeDeflated() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCube(deflate: true))
        XCTAssertEqual(doc.unit, .millimeter)
        XCTAssertEqual(doc.plates.count, 1)
        let plate = doc.plates[0]
        XCTAssertEqual(plate.id, 1)
        XCTAssertEqual(plate.name, "Plate 1")
        XCTAssertNil(plate.thumbnail)
        XCTAssertNil(plate.stats)
        XCTAssertTrue(plate.palette.isEmpty)
        XCTAssertNil(plate.mesh.triangleColorIndices)
        XCTAssertEqual(plate.mesh.positions.count, 8)
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        try assertBoundingBox(plate.mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
        XCTAssertNil(doc.packageThumbnail)
        XCTAssertNil(doc.primaryThumbnail)
    }

    func testMinimalCubeStored() throws {
        // STORE vs. DEFLATE must not change the parsed result at all.
        let deflated = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCube(deflate: true))
        let stored = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCube(deflate: false))
        XCTAssertEqual(stored.plates[0].mesh.triangleCount, deflated.plates[0].mesh.triangleCount)
        XCTAssertEqual(stored.plates[0].mesh.positions, deflated.plates[0].mesh.positions)
        XCTAssertEqual(stored.plates[0].mesh.indices, deflated.plates[0].mesh.indices)
    }

    func testMinimalCubeWithForcedZip64ExtraFields() throws {
        // OnShape-style packages emit ZIP64 extra fields even for tiny
        // entries; the resolved geometry must be identical either way.
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCube(deflate: true, forceZip64ExtraFields: true))
        XCTAssertEqual(doc.plates[0].mesh.triangleCount, 12)
        try assertBoundingBox(doc.plates[0].mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
    }

    // MARK: - Component graph / transform composition

    func testComponentFanOutDuplicatesGeometryWithoutTransforming() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.componentFanOut(depth: 2, fanOut: 3))
        let plate = doc.plates[0]
        // 3^2 == 9 leaf instances, none transformed, all overlapping.
        XCTAssertEqual(plate.mesh.triangleCount, 9 * 12)
        XCTAssertEqual(plate.mesh.positions.count, 9 * 8)
        try assertBoundingBox(plate.mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
    }

    func testTranslatedComponentComposesTransform() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.translatedComponent())
        let plate = doc.plates[0]
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        try assertBoundingBox(plate.mesh, min: SIMD3<Float>(10, 20, 30), max: SIMD3<Float>(30, 40, 50))
    }

    func testProductionExtensionCubeResolvesCrossPartComponent() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.productionExtensionCube())
        let plate = doc.plates[0]
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        XCTAssertEqual(plate.mesh.positions.count, 8)
        try assertBoundingBox(plate.mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
    }

    // MARK: - Bambu plate/palette/stats fixtures

    func testBambuTwoPlates() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.bambuTwoPlates())
        XCTAssertEqual(doc.plates.count, 2)

        let plate1 = doc.plates[0]
        XCTAssertEqual(plate1.id, 1)
        XCTAssertEqual(plate1.name, "Cube A")
        try assertBoundingBox(plate1.mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
        XCTAssertEqual(plate1.mesh.triangleCount, 12)
        XCTAssertEqual(plate1.thumbnail?.count, TinyPNGFixture.data.count)
        XCTAssertTrue(plate1.palette.isEmpty, "bambuTwoPlates has no project_settings.config, so there's no palette")
        XCTAssertNil(plate1.mesh.triangleColorIndices)
        let stats1 = try XCTUnwrap(plate1.stats)
        XCTAssertEqual(stats1.predictionSeconds, 3600)
        XCTAssertEqual(stats1.weightGrams, 12.5)
        XCTAssertEqual(stats1.printerModel, "X1C")
        XCTAssertEqual(stats1.filaments.count, 1)
        XCTAssertEqual(stats1.filaments[0].usedGrams, 12.5)

        let plate2 = doc.plates[1]
        XCTAssertEqual(plate2.id, 2)
        // Empty `plater_name` falls back to "Plate <id>".
        XCTAssertEqual(plate2.name, "Plate 2")
        try assertBoundingBox(plate2.mesh, min: SIMD3<Float>(50, 0, 0), max: SIMD3<Float>(70, 20, 20))
        XCTAssertEqual(plate2.mesh.triangleCount, 12)
        XCTAssertEqual(plate2.thumbnail?.count, TinyPNGFixture.data.count)
        // No Metadata/plate_2.json in this fixture.
        XCTAssertNil(plate2.stats)

        XCTAssertEqual(doc.packageThumbnail?.count, TinyPNGFixture.data.count)
        XCTAssertEqual(doc.primaryThumbnail?.count, plate1.thumbnail?.count)
    }

    func testBambuPaintedTriangles() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.bambuPaintedTriangles())
        XCTAssertEqual(doc.plates.count, 1)
        let plate = doc.plates[0]
        XCTAssertEqual(plate.name, "Painted Cube")
        XCTAssertEqual(plate.palette, ["#FF0000", "#00FF00"])
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        // Triangle 0 is explicitly painted extruder 2 (palette index 1);
        // every other triangle falls back to the object's base extruder 1
        // (palette index 0).
        XCTAssertEqual(plate.mesh.triangleColorIndices, [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(plate.hasColorData)
    }

    func testBambuMultiPlateProject() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.bambuMultiPlateProject())
        XCTAssertEqual(doc.plates.count, 2)
        let palette = ["#FF0000", "#00FF00", "#0000FF"]

        let plate1 = doc.plates[0]
        XCTAssertEqual(plate1.id, 1)
        XCTAssertEqual(plate1.name, "Cube A")
        XCTAssertEqual(plate1.palette, palette)
        XCTAssertEqual(plate1.mesh.triangleCount, 12)
        XCTAssertEqual(plate1.mesh.positions.count, 8)
        try assertBoundingBox(plate1.mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
        // Triangle 0 painted extruder 2 (index 1); the rest fall back to
        // object 1's base extruder 1 (index 0).
        XCTAssertEqual(plate1.mesh.triangleColorIndices, [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(plate1.thumbnail?.count, TinyPNGFixture.data.count)
        let stats1 = try XCTUnwrap(plate1.stats)
        XCTAssertEqual(stats1.predictionSeconds, 5400)
        XCTAssertEqual(stats1.weightGrams, 15.2)
        XCTAssertEqual(stats1.printerModel, "X1C")
        XCTAssertEqual(stats1.filaments.map(\.colorHex), palette)
        XCTAssertEqual(stats1.filaments.map(\.type), ["PLA", "PETG", "ABS"])

        let plate2 = doc.plates[1]
        XCTAssertEqual(plate2.id, 2)
        XCTAssertEqual(plate2.name, "Cube B")
        XCTAssertEqual(plate2.palette, palette)
        XCTAssertEqual(plate2.mesh.triangleCount, 12)
        try assertBoundingBox(plate2.mesh, min: SIMD3<Float>(50, 0, 0), max: SIMD3<Float>(70, 20, 20))
        // No painting on object 2; base extruder 3 -> every triangle at
        // palette index 2.
        XCTAssertEqual(plate2.mesh.triangleColorIndices, [UInt8](repeating: 2, count: 12))
        let stats2 = try XCTUnwrap(plate2.stats)
        XCTAssertEqual(stats2.predictionSeconds, 2700)
        XCTAssertEqual(stats2.weightGrams, 8.4)

        XCTAssertEqual(doc.packageThumbnail?.count, TinyPNGFixture.data.count)
        // Plate 1 mixes two colors (painted + base), so there's something to
        // toggle; plate 2 is a single uniform color, so there isn't.
        XCTAssertTrue(plate1.hasColorData)
        XCTAssertFalse(plate2.hasColorData)
    }

    // MARK: - object type exclusion

    func testObjectTypesFixtureExcludesSupportAndOther() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.objectTypesFixture())
        let plate = doc.plates[0]
        // model (12) + support (excluded) + other (excluded) + solidsupport (12) == 24.
        XCTAssertEqual(plate.mesh.triangleCount, 24)
        XCTAssertEqual(plate.mesh.positions.count, 16)
        try assertBoundingBox(plate.mesh, min: .zero, max: SIMD3<Float>(320, 20, 20))
    }

    // MARK: - Adversarial-but-still-loadable 3MF fixtures

    func testTriangleOutOfRangeCubeDropsOnlyBadTriangle() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.triangleOutOfRangeCube())
        let plate = doc.plates[0]
        XCTAssertEqual(plate.mesh.triangleCount, 11)
        XCTAssertEqual(plate.mesh.positions.count, 8)
        try assertBoundingBox(plate.mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
    }

    func testHugeDigitTriangleIndexCubeDropsOnlyBadTriangle() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.hugeDigitTriangleIndexCube())
        XCTAssertEqual(doc.plates[0].mesh.triangleCount, 11)
    }

    func testHugeExponentVertexCubeClampsToFiniteBoundingBox() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.hugeExponentVertexCube())
        let plate = doc.plates[0]
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        let box = try XCTUnwrap(plate.mesh.boundingBox)
        XCTAssertTrue(box.min.x.isFinite && box.max.x.isFinite)
    }

    func testMinimalCubeWithFakeEOCDInCommentStillLoads() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCubeWithFakeEOCDInComment())
        XCTAssertEqual(doc.plates[0].mesh.triangleCount, 12)
        try assertBoundingBox(doc.plates[0].mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
    }

    func testLyingHeaderEntryIsRejected() {
        XCTAssertThrowsError(try ThreeMFLoader().load(data: ThreeMFFixtureFactory.lyingHeaderEntry()))
    }

    // MARK: - STL / OBJ / PLY cube fixtures (all share the same cube geometry)

    private func assertFixtureCube(_ mesh: TriangleMesh) throws {
        XCTAssertEqual(mesh.triangleCount, 12)
        XCTAssertEqual(mesh.positions.count, 8)
        try assertBoundingBox(mesh, min: .zero, max: SIMD3<Float>(20, 20, 20))
    }

    func testSTLBinaryCube() throws {
        try assertFixtureCube(try STLParser.parse(data: ThreeMFFixtureFactory.stlBinaryCube()))
    }

    func testSTLBinaryCubeWithTrailingBytes() throws {
        try assertFixtureCube(try STLParser.parse(data: ThreeMFFixtureFactory.stlBinaryCubeWithTrailingBytes()))
    }

    func testSTLBinaryCubeWithSolidPrefix() throws {
        try assertFixtureCube(try STLParser.parse(data: ThreeMFFixtureFactory.stlBinaryCubeWithSolidPrefix()))
    }

    func testSTLBinaryCubeWithZeroDeclaredCount() throws {
        try assertFixtureCube(try STLParser.parse(data: ThreeMFFixtureFactory.stlBinaryCubeWithZeroDeclaredCount()))
    }

    func testSTLASCIICube() throws {
        try assertFixtureCube(try STLParser.parse(data: ThreeMFFixtureFactory.stlASCIICube()))
    }

    func testOBJCube() throws {
        try assertFixtureCube(try OBJParser.parse(data: ThreeMFFixtureFactory.objCube()))
    }

    func testPLYASCIICube() throws {
        try assertFixtureCube(try PLYParser.parse(data: ThreeMFFixtureFactory.plyASCIICube()))
    }

    func testPLYASCIICubeWithHugeFaceIndexThrows() {
        XCTAssertThrowsError(try PLYParser.parse(data: ThreeMFFixtureFactory.plyASCIICubeWithHugeFaceIndex()))
    }

    func testPLYBinaryLittleEndianCube() throws {
        try assertFixtureCube(try PLYParser.parse(data: ThreeMFFixtureFactory.plyBinaryLECube()))
    }

    func testPLYBinaryBigEndianCube() throws {
        try assertFixtureCube(try PLYParser.parse(data: ThreeMFFixtureFactory.plyBinaryBECube()))
    }

    // MARK: - Small hand-built OBJ/PLY/STL inputs (independent of the factory's cube)

    /// A single upward-facing right triangle: (0,0,0), (4,0,0), (0,3,0).
    func testHandBuiltASCIIOBJTriangle() throws {
        let obj = "v 0 0 0\nv 4 0 0\nv 0 3 0\nf 1 2 3\n"
        let mesh = try OBJParser.parse(data: Data(obj.utf8))
        XCTAssertEqual(mesh.triangleCount, 1)
        XCTAssertEqual(mesh.positions, [SIMD3<Float>(0, 0, 0), SIMD3<Float>(4, 0, 0), SIMD3<Float>(0, 3, 0)])
        XCTAssertEqual(mesh.indices, [0, 1, 2])
        try assertBoundingBox(mesh, min: .zero, max: SIMD3<Float>(4, 3, 0))
    }

    /// A single triangle as ASCII PLY.
    func testHandBuiltASCIIPLYTriangle() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0
        5 0 0
        0 5 0
        3 0 1 2

        """
        let mesh = try PLYParser.parse(data: Data(ply.utf8))
        XCTAssertEqual(mesh.triangleCount, 1)
        XCTAssertEqual(mesh.positions, [SIMD3<Float>(0, 0, 0), SIMD3<Float>(5, 0, 0), SIMD3<Float>(0, 5, 0)])
        try assertBoundingBox(mesh, min: .zero, max: SIMD3<Float>(5, 5, 0))
    }

    /// A single triangle as binary (little-endian) STL: 80-byte header,
    /// UInt32 triangle count, one 50-byte record.
    func testHandBuiltBinarySTLTriangle() throws {
        var data = Data(count: 80)
        var count = UInt32(1).littleEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        data.append(contentsOf: [UInt8](repeating: 0, count: 12)) // normal, unused
        let vertices: [(Float, Float, Float)] = [(0, 0, 0), (2, 0, 0), (0, 2, 0)]
        for v in vertices {
            for component in [v.0, v.1, v.2] {
                var bits = component.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
        }
        data.append(contentsOf: [0, 0]) // attribute byte count

        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 1)
        XCTAssertEqual(mesh.positions, [SIMD3<Float>(0, 0, 0), SIMD3<Float>(2, 0, 0), SIMD3<Float>(0, 2, 0)])
        try assertBoundingBox(mesh, min: .zero, max: SIMD3<Float>(2, 2, 0))
    }

    // MARK: - End-to-end via ModelLoader, not just the format parsers directly

    func testModelLoaderEndToEndForEachMeshFormat() throws {
        let loader = ModelLoader()
        for (format, data): (ModelFormat, Data) in [
            (.stl, ThreeMFFixtureFactory.stlBinaryCube()),
            (.obj, ThreeMFFixtureFactory.objCube()),
            (.ply, ThreeMFFixtureFactory.plyASCIICube())
        ] {
            let doc = try loader.load(data: data, format: format, name: "golden-\(format.rawValue)")
            XCTAssertEqual(doc.plates.count, 1)
            XCTAssertEqual(doc.plates[0].name, "golden-\(format.rawValue)")
            try assertFixtureCube(doc.plates[0].mesh)
        }
    }
}
