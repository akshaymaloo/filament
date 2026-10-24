import XCTest
@testable import FilamentKit
import FilamentTestSupport

/// Guards the committed `Filament Sample.3mf` against drifting from, or being
/// corrupted relative to, `FilamentFixtureFactory.sampleSpool()`.
final class BundledSampleTests: XCTestCase {
    private var sampleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Filament/Resources/Filament Sample.3mf")
    }

    func testBundledSampleLoadsWithGeometryAndColor() throws {
        let document = try ModelLoader().load(url: sampleURL)
        XCTAssertFalse(document.plates.isEmpty)
        XCTAssertFalse(document.hasNoGeometry)
        XCTAssertGreaterThan(document.plates[document.defaultPlateIndex].mesh.triangleCount, 0)
        let colors = document.plates.flatMap { $0.mesh.triangleColorIndices ?? [] }
        XCTAssertFalse(colors.isEmpty, "sample must carry per-triangle color data")
        XCTAssertGreaterThan(Set(colors).count, 1)
        XCTAssertTrue(document.plates.contains { !$0.palette.isEmpty })
    }

    func testBundledSampleMatchesFreshlyGeneratedSample() throws {
        let committed = try ModelLoader().load(url: sampleURL)
        let fresh = try ModelLoader().load(data: FilamentFixtureFactory.sampleSpool(), format: .threeMF, name: "sample")
        XCTAssertEqual(committed.plates.count, fresh.plates.count)
        XCTAssertEqual(committed.unit, fresh.unit)
        for (a, b) in zip(committed.plates, fresh.plates) {
            XCTAssertEqual(a.mesh.triangleCount, b.mesh.triangleCount)
            XCTAssertEqual(a.mesh.positions.count, b.mesh.positions.count)
            XCTAssertEqual(a.mesh.triangleColorIndices, b.mesh.triangleColorIndices)
            XCTAssertEqual(a.palette, b.palette)
        }
        XCTAssertEqual(try Data(contentsOf: sampleURL), FilamentFixtureFactory.sampleSpool(),
                       "run scripts/make-sample-model.sh to regenerate the bundled sample")
    }
}
