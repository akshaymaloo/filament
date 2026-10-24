import XCTest
@testable import FilamentKit
import FilamentTestSupport

final class LoadFailureMessageTests: XCTestCase {
    private let damaged = "The file may be damaged, or it isn’t a valid 3MF file."

    private func message(_ error: Error, fileName: String? = nil, context: LoadFailureMessage.Context = .preview) -> LoadFailureMessage {
        LoadFailureMessage(error: error, fileName: fileName, context: context)
    }

    func testDamagedArchiveErrors() {
        let errors: [FilamentError] = [.notAZipArchive, .corruptArchive("bad CRC"), .unsupportedCompression(method: 99)]
        for error in errors {
            let result = message(error)
            XCTAssertEqual(result.detail, damaged)
            XCTAssertFalse(result.suggestsOpeningInApp)
        }
    }

    func testMissingModelPart() {
        XCTAssertEqual(message(FilamentError.missingModelPart).detail, "The file doesn’t contain a 3D model.")
    }

    func testMalformedDataDoesNotLeakParserDetail() {
        for error in [FilamentError.malformedXML("line 3: unexpected <"), .malformedMesh("bad vertex")] {
            let result = message(error)
            XCTAssertEqual(result.detail, "The model data in this file couldn’t be read.")
            XCTAssertFalse(result.suggestsOpeningInApp)
        }
    }

    func testMeshTooLargeSuggestsOpeningInAppForPreview() {
        let result = message(FilamentError.meshTooLarge(triangles: 25_000_000, limit: 20_000_000))
        XCTAssertEqual(result.detail, "This model is too large to preview (25,000,000 triangles).")
        XCTAssertTrue(result.suggestsOpeningInApp)
    }

    func testMeshTooLargeDoesNotSuggestOpeningInAppWhenAlreadyOpening() {
        let result = message(FilamentError.meshTooLarge(triangles: 5, limit: 1), context: .open)
        XCTAssertEqual(result.detail, "This model is too large to open (5 triangles).")
        XCTAssertFalse(result.suggestsOpeningInApp)
    }

    func testArchiveLimitsDoNotSuggestOpeningInApp() {
        let errors: [FilamentError] = [.entryTooLarge(path: "a", size: 2, limit: 1), .archiveTooLarge(limit: 1)]
        for error in errors {
            let result = message(error)
            XCTAssertEqual(result.detail, "This file is too large to preview.")
            XCTAssertFalse(result.suggestsOpeningInApp)
        }
        XCTAssertEqual(message(errors[0], context: .open).detail, "This file is too large to open.")
    }

    func testCancelledStillHasMessage() {
        XCTAssertEqual(message(FilamentError.cancelled).detail, "Loading was cancelled.")
    }

    func testNonFilamentErrorsAreGeneric() {
        let result = message(CocoaError(.fileReadNoPermission))
        XCTAssertEqual(result.detail, "The file couldn’t be read.")
        XCTAssertFalse(result.suggestsOpeningInApp)
    }

    func testTitleUsesFileNameAndContext() {
        XCTAssertEqual(message(FilamentError.notAZipArchive).title, "Couldn’t Preview File")
        XCTAssertEqual(message(FilamentError.notAZipArchive, fileName: "").title, "Couldn’t Preview File")
        XCTAssertEqual(message(FilamentError.notAZipArchive, fileName: "a.3mf").title, "Couldn’t Preview “a.3mf”")
        XCTAssertEqual(message(FilamentError.notAZipArchive, fileName: "a.3mf", context: .open).title, "Couldn’t Open “a.3mf”")
    }

    func testEmptyModelMessage() {
        let result = LoadFailureMessage.emptyModel(fileName: "x.stl")
        XCTAssertEqual(result.title, "Couldn’t Preview “x.stl”")
        XCTAssertEqual(result.detail, "This file doesn’t contain any 3D geometry.")
        XCTAssertFalse(result.suggestsOpeningInApp)
        XCTAssertEqual(LoadFailureMessage.emptyModel(context: .open).title, "Couldn’t Open File")
    }

    func testUnsupportedFormatMessage() {
        let result = LoadFailureMessage.unsupportedFormat(fileName: "notes.txt")
        XCTAssertEqual(result.title, "Couldn’t Open “notes.txt”")
        XCTAssertEqual(result.detail, "Filament opens 3MF, STL, OBJ, and PLY files.")
    }

    func testCancellationDetection() {
        XCTAssertTrue(LoadFailureMessage.isCancellation(FilamentError.cancelled))
        XCTAssertTrue(LoadFailureMessage.isCancellation(CancellationError()))
        XCTAssertFalse(LoadFailureMessage.isCancellation(FilamentError.notAZipArchive))
        XCTAssertFalse(LoadFailureMessage.isCancellation(CocoaError(.fileReadNoSuchFile)))
    }

    func testHasNoGeometry() throws {
        let empty = BuildPlate(id: 1, name: "Empty", thumbnail: nil, mesh: TriangleMesh(), stats: nil)
        XCTAssertTrue(ModelDocument(unit: .millimeter, plates: [empty], packageThumbnail: nil).hasNoGeometry)
        XCTAssertTrue(ModelDocument(unit: .millimeter, plates: [], packageThumbnail: nil).hasNoGeometry)

        let cube = try ModelLoader().load(data: FilamentFixtureFactory.stlBinaryCube(), format: .stl, name: "cube")
        XCTAssertFalse(cube.hasNoGeometry)
        let mixed = ModelDocument(unit: .millimeter, plates: [empty] + cube.plates, packageThumbnail: nil)
        XCTAssertFalse(mixed.hasNoGeometry)
    }

    func testRealLoaderFailuresMapToFriendlyCopy() {
        let loader = ModelLoader()
        XCTAssertThrowsError(try loader.load(data: Data("nope".utf8), format: .threeMF, name: "x")) { error in
            XCTAssertEqual(self.message(error).detail, self.damaged)
        }
    }

    func testSampleModelIsMultiColorAndSmall() throws {
        let data = FilamentFixtureFactory.sampleSpool()
        XCTAssertLessThan(data.count, 300 * 1024)
        let plate = try XCTUnwrap(ThreeMFLoader().load(data: data).plates.first)
        XCTAssertTrue(plate.hasColorData)
        XCTAssertGreaterThanOrEqual(Set(plate.mesh.triangleColorIndices ?? []).count, 3)
        XCTAssertEqual(data, FilamentFixtureFactory.sampleSpool())
    }
}
