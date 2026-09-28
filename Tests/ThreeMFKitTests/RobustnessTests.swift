import XCTest
@testable import ThreeMFKit
#if canImport(SceneKit)
import SceneKit
#endif

/// Covers the robustness/security fixes: out-of-range/overflowing 3MF
/// indices, the ZIP EOCD disambiguation, the triangle/time budget and
/// cancellation plumbing, stricter-but-more-tolerant STL sniffing, excluding
/// `support`/`other` 3MF objects from the render, the aggregate zip-bomb cap
/// (plus previously-unlimited metadata reads), and assorted integer-overflow
/// crash risks in the mesh format parsers.
final class TriangleIndexBoundsTests: XCTestCase {
    func testOutOfRangeTriangleIsDroppedOthersKept() throws {
        let data = ThreeMFFixtureFactory.triangleOutOfRangeCube()
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)
        XCTAssertEqual(plate.mesh.triangleCount, 11)
        XCTAssertEqual(plate.mesh.positions.count, 8)
    }

    func testHugeDigitTriangleIndexOverflowIsDroppedOthersKept() throws {
        // v3="99999999999999999999" (20 digits) must not trap parseInt's
        // overflow arithmetic; the resulting (clamped, then out-of-range)
        // index is filtered out like any other bad index.
        let data = ThreeMFFixtureFactory.hugeDigitTriangleIndexCube()
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)
        XCTAssertEqual(plate.mesh.triangleCount, 11)
    }

    func testHugeExponentVertexCoordinateDoesNotCrashOrPoisonBoundingBox() throws {
        let data = ThreeMFFixtureFactory.hugeExponentVertexCube()
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)
        // The vertex itself isn't dropped (indices stay valid); its
        // non-finite coordinate is clamped to 0 instead.
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        let bbox = try XCTUnwrap(plate.mesh.boundingBox)
        XCTAssertTrue(bbox.min.x.isFinite && bbox.min.y.isFinite && bbox.min.z.isFinite)
        XCTAssertTrue(bbox.max.x.isFinite && bbox.max.y.isFinite && bbox.max.z.isFinite)
    }

#if canImport(SceneKit)
    func testMakeGeometryExcludesBadIndexKeepsParallelColorIndices() throws {
        // 4 vertices, 2 triangles; the second triangle references vertex 99
        // (out of range). `triangleColorIndices` must stay parallel with the
        // *sanitized* triangle count once the bad triangle is dropped.
        let positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0)
        ]
        let indices: [UInt32] = [0, 1, 2, 1, 99, 3]
        let colorIndices: [UInt8] = [0, 1]
        let mesh = TriangleMesh(positions: positions, indices: indices, triangleColorIndices: colorIndices)
        XCTAssertEqual(mesh.triangleCount, 2, "raw mesh is unsanitized until rendering")

        let geometry = try XCTUnwrap(mesh.makeGeometry())
        let totalPrimitives = geometry.elements.reduce(0) { $0 + $1.primitiveCount }
        XCTAssertEqual(totalPrimitives, 1, "the out-of-range triangle must never reach SCNGeometryElement")
    }
#endif
}

final class ZipArchiveEOCDTests: XCTestCase {
    func testTrailingCommentWithFakeEOCDSignatureStillOpens() throws {
        let data = ThreeMFFixtureFactory.minimalCubeWithFakeEOCDInComment()
        let doc = try ThreeMFLoader().load(data: data)
        XCTAssertEqual(doc.plates.count, 1)
        XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
    }
}

final class ObjectTypeExclusionTests: XCTestCase {
    func testSupportAndOtherExcludedSolidSupportKept() throws {
        let data = ThreeMFFixtureFactory.objectTypesFixture()
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)
        // model (12) + support (excluded, 0) + other (excluded, 0) + solidsupport (12) == 24.
        XCTAssertEqual(plate.mesh.triangleCount, 24)
    }
}

final class ZipBombCapTests: XCTestCase {
    func testTinyMaxTotalUncompressedBytesRejectsPackage() {
        var options = ThreeMFLoader.Options.default
        options.maxTotalUncompressedBytes = 32
        let data = ThreeMFFixtureFactory.minimalCube(deflate: true)
        XCTAssertThrowsError(try ThreeMFLoader(options: options).load(data: data))
    }

    func testTinyMaxMetadataBytesRejectsPackage() {
        var options = ThreeMFLoader.Options.default
        options.maxMetadataBytes = 8
        let data = ThreeMFFixtureFactory.bambuTwoPlates()
        XCTAssertThrowsError(try ThreeMFLoader(options: options).load(data: data))
    }

    func testLyingDeflateRatioRejectedBeforeAllocating() {
        var options = ThreeMFLoader.Options.default
        // Raise the per-part cap well above the claimed size, so the ratio
        // check (not the plain per-entry size limit) is what fires.
        options.maxModelPartBytes = 2 * 1024 * 1024 * 1024
        let data = ThreeMFFixtureFactory.lyingHeaderEntry(claimedUncompressedBytes: 1024 * 1024 * 1024)
        XCTAssertThrowsError(try ThreeMFLoader(options: options).load(data: data))
    }
}

final class TriangleBudgetAndCancellationTests: XCTestCase {
    func testMaxTrianglesExceededThrowsMeshTooLarge3MF() {
        var options = ThreeMFLoader.Options.default
        options.maxTriangles = 5
        let data = ThreeMFFixtureFactory.minimalCube(deflate: false)
        XCTAssertThrowsError(try ThreeMFLoader(options: options).load(data: data)) { error in
            guard case ThreeMFError.meshTooLarge = error else {
                return XCTFail("expected .meshTooLarge, got \(error)")
            }
        }
    }

    func testShouldCancelThrowsCancelled3MF() {
        var options = ThreeMFLoader.Options.default
        options.shouldCancel = { true }
        let data = ThreeMFFixtureFactory.minimalCube(deflate: false)
        XCTAssertThrowsError(try ThreeMFLoader(options: options).load(data: data)) { error in
            guard case ThreeMFError.cancelled = error else {
                return XCTFail("expected .cancelled, got \(error)")
            }
        }
    }

    func testMaxTrianglesExceededThrowsMeshTooLargeSTL() {
        let data = ThreeMFFixtureFactory.stlBinaryCube()
        XCTAssertThrowsError(try STLParser.parse(data: data, maxTriangles: 5)) { error in
            guard case ThreeMFError.meshTooLarge = error else {
                return XCTFail("expected .meshTooLarge, got \(error)")
            }
        }
    }

    func testShouldCancelThrowsCancelledSTL() {
        let data = ThreeMFFixtureFactory.stlBinaryCube()
        XCTAssertThrowsError(try STLParser.parse(data: data, shouldCancel: { true })) { error in
            guard case ThreeMFError.cancelled = error else {
                return XCTFail("expected .cancelled, got \(error)")
            }
        }
    }
}

final class STLDetectionTests: XCTestCase {
    func testBinaryWithTrailingBytesStillParsesAsBinary() throws {
        let data = ThreeMFFixtureFactory.stlBinaryCubeWithTrailingBytes()
        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)
    }

    func testBinaryWithSolidPrefixStillParsesAsBinaryWhenExactSizeMatches() throws {
        let data = ThreeMFFixtureFactory.stlBinaryCubeWithSolidPrefix()
        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)
    }

    func testBinaryWithZeroDeclaredCountParsesViaBodySizeFallback() throws {
        let data = ThreeMFFixtureFactory.stlBinaryCubeWithZeroDeclaredCount()
        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)
    }

    func testASCIIStillParses() throws {
        let data = ThreeMFFixtureFactory.stlASCIICube()
        let mesh = try STLParser.parse(data: data)
        XCTAssertEqual(mesh.triangleCount, 12)
    }

    func testModelLoaderSniffingDetectsTrailingBytesBinarySTLWithoutExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ThreeMFKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("mystery-file")
        try ThreeMFFixtureFactory.stlBinaryCubeWithTrailingBytes().write(to: fileURL)

        let doc = try ModelLoader().load(url: fileURL)
        XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
    }
}

final class PLYOverflowGuardTests: XCTestCase {
    func testHugeFaceIndexThrowsMalformedMeshInsteadOfTrapping() {
        let data = ThreeMFFixtureFactory.plyASCIICubeWithHugeFaceIndex()
        XCTAssertThrowsError(try PLYParser.parse(data: data)) { error in
            guard case ThreeMFError.malformedMesh = error else {
                return XCTFail("expected .malformedMesh, got \(error)")
            }
        }
    }
}

final class ComponentFanOutTests: XCTestCase {
    func testFanOutExceedingTriangleBudgetThrowsBeforeMaterializing() {
        // 10^6 cube instances (12M triangles) from a few-KB package.
        let data = ThreeMFFixtureFactory.componentFanOut(depth: 6, fanOut: 10)
        var options = ThreeMFLoader.Options.default
        options.maxTriangles = 10_000
        XCTAssertThrowsError(try ThreeMFLoader(options: options).load(data: data)) { error in
            guard case ThreeMFError.meshTooLarge = error else {
                return XCTFail("expected .meshTooLarge, got \(error)")
            }
        }
    }

    func testFanOutOfEmptyLeavesHitsVisitCap() {
        // Leaves are excluded (no triangles), so only the visit cap can stop
        // 10^7 recursive object references.
        let data = ThreeMFFixtureFactory.componentFanOut(depth: 7, fanOut: 10, leafType: "support")
        XCTAssertThrowsError(try ThreeMFLoader().load(data: data)) { error in
            guard case ThreeMFError.malformedXML = error else {
                return XCTFail("expected .malformedXML, got \(error)")
            }
        }
    }

    func testSmallFanOutStillResolves() throws {
        let data = ThreeMFFixtureFactory.componentFanOut(depth: 2, fanOut: 3)
        let doc = try ThreeMFLoader().load(data: data)
        XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 9 * 12)
    }
}

final class SniffingOrderTests: XCTestCase {
    func testExtensionlessOBJWhoseSizeLooksLikeBinarySTLIsDetectedAsOBJ() throws {
        // Pad with an OBJ comment line so (size - 84) is a multiple of 50,
        // which the lenient binary-STL body-size heuristic would also accept.
        var obj = ThreeMFFixtureFactory.objCube()
        obj.append(contentsOf: Array("\n# ".utf8))
        let padding = (50 - (obj.count + 1 - 84) % 50) % 50
        obj.append(contentsOf: [UInt8](repeating: UInt8(ascii: "x"), count: padding))
        obj.append(UInt8(ascii: "\n"))
        XCTAssertEqual((obj.count - 84) % 50, 0)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ThreeMFKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("mystery-obj")
        try obj.write(to: fileURL)

        let doc = try ModelLoader().load(url: fileURL)
        XCTAssertEqual(doc.plates.first?.mesh.triangleCount, 12)
    }
}
