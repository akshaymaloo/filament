import XCTest
@testable import FilamentKit

final class DefaultPlateTests: XCTestCase {
    private func plate(_ id: Int, triangles: Int) -> BuildPlate {
        var mesh = TriangleMesh()
        if triangles > 0 {
            mesh.positions = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)]
            mesh.indices = Array(repeating: [0, 1, 2], count: triangles).flatMap { $0 }
        }
        return BuildPlate(id: id, name: "Plate \(id)", thumbnail: nil, mesh: mesh, stats: nil)
    }

    private func index(_ counts: [Int]) -> Int {
        let plates = counts.enumerated().map { plate($0.offset + 1, triangles: $0.element) }
        return ModelDocument(unit: .millimeter, plates: plates, packageThumbnail: nil).defaultPlateIndex
    }

    func testAllEmptyFallsBackToFirst() { XCTAssertEqual(index([0, 0, 0]), 0) }
    func testFirstEmptySkipsToNextNonEmpty() { XCTAssertEqual(index([0, 2, 1]), 1) }
    func testAllNonEmptyPicksFirst() { XCTAssertEqual(index([1, 2, 3]), 0) }
    func testSinglePlate() {
        XCTAssertEqual(index([4]), 0)
        XCTAssertEqual(index([0]), 0)
    }
    func testLeadingEmptyPlatesSkipped() { XCTAssertEqual(index([0, 0, 5]), 2) }
}
