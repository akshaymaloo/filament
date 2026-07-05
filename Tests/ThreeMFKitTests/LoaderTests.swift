import XCTest
@testable import ThreeMFKit

final class MinimalCubeTests: XCTestCase {
    func testStoreMethodLoad() throws {
        try assertCube(deflate: false)
    }

    func testDeflateMethodLoad() throws {
        try assertCube(deflate: true)
    }

    private func assertCube(deflate: Bool) throws {
        let data = ThreeMFFixtureFactory.minimalCube(deflate: deflate)
        let loader = ThreeMFLoader()
        let doc = try loader.load(data: data)

        XCTAssertEqual(doc.unit, .millimeter)
        XCTAssertEqual(doc.plates.count, 1)

        let plate = try XCTUnwrap(doc.plates.first)
        XCTAssertEqual(plate.id, 1)
        XCTAssertEqual(plate.mesh.triangleCount, 12)
        XCTAssertEqual(plate.mesh.positions.count, 8)

        let bbox = try XCTUnwrap(plate.mesh.boundingBox)
        XCTAssertEqual(bbox.min, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(bbox.max, SIMD3<Float>(20, 20, 20))

        XCTAssertNil(doc.packageThumbnail)
        XCTAssertNil(doc.primaryThumbnail)
    }
}

final class TranslatedComponentTests: XCTestCase {
    func testComponentTransformComposition() throws {
        let data = ThreeMFFixtureFactory.translatedComponent()
        let loader = ThreeMFLoader()
        let doc = try loader.load(data: data)

        XCTAssertEqual(doc.plates.count, 1)
        let plate = try XCTUnwrap(doc.plates.first)
        XCTAssertEqual(plate.mesh.triangleCount, 12)

        let bbox = try XCTUnwrap(plate.mesh.boundingBox)
        XCTAssertEqual(bbox.min, SIMD3<Float>(10, 20, 30))
        XCTAssertEqual(bbox.max, SIMD3<Float>(30, 40, 50))
    }
}

final class ProductionExtensionCubeTests: XCTestCase {
    func testCrossPartComponentResolution() throws {
        let data = ThreeMFFixtureFactory.productionExtensionCube()
        let loader = ThreeMFLoader()
        let doc = try loader.load(data: data)

        XCTAssertEqual(doc.plates.count, 1)
        let plate = try XCTUnwrap(doc.plates.first)
        XCTAssertEqual(plate.mesh.triangleCount, 12)

        let bbox = try XCTUnwrap(plate.mesh.boundingBox)
        XCTAssertEqual(bbox.min, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(bbox.max, SIMD3<Float>(20, 20, 20))
    }
}

final class BambuTwoPlatesTests: XCTestCase {
    func testPlateEnumerationThumbnailsAndStats() throws {
        let data = ThreeMFFixtureFactory.bambuTwoPlates()
        let loader = ThreeMFLoader()
        let doc = try loader.load(data: data)

        XCTAssertEqual(doc.plates.count, 2)
        XCTAssertEqual(doc.plates.map { $0.id }, [1, 2])

        let plate1 = try XCTUnwrap(doc.plates.first(where: { $0.id == 1 }))
        XCTAssertEqual(plate1.name, "Cube A")
        let thumbnail1 = try XCTUnwrap(plate1.thumbnail)
        XCTAssertTrue(isPNG(thumbnail1))
        let stats1 = try XCTUnwrap(plate1.stats)
        XCTAssertEqual(stats1.predictionSeconds, 3600)
        XCTAssertEqual(stats1.weightGrams, 12.5)
        XCTAssertEqual(plate1.mesh.triangleCount, 12)

        let plate2 = try XCTUnwrap(doc.plates.first(where: { $0.id == 2 }))
        XCTAssertEqual(plate2.name, "Plate 2")
        XCTAssertEqual(plate2.mesh.triangleCount, 12)

        XCTAssertNotNil(doc.packageThumbnail)
        XCTAssertNotNil(doc.primaryThumbnail)

        let quickThumb = try loader.extractPrimaryThumbnail(data: data)
        let unwrappedQuickThumb = try XCTUnwrap(quickThumb)
        XCTAssertTrue(isPNG(unwrappedQuickThumb))
    }

    func testThumbnailOnlyFastPath() throws {
        let data = ThreeMFFixtureFactory.bambuTwoPlates()
        let loader = ThreeMFLoader(options: .thumbnailOnly)
        let doc = try loader.load(data: data)

        XCTAssertEqual(doc.plates.count, 2)
        XCTAssertTrue(doc.plates.allSatisfy { $0.mesh.isEmpty })
        XCTAssertNotNil(doc.plates.first(where: { $0.id == 1 })?.thumbnail)
    }

    private func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        guard data.count >= 8 else { return false }
        return Array(data.prefix(8)) == signature
    }
}

final class ErrorHandlingTests: XCTestCase {
    func testMalformedDataThrows() {
        let loader = ThreeMFLoader()
        XCTAssertThrowsError(try loader.load(data: Data("not a zip".utf8)))
    }
}
