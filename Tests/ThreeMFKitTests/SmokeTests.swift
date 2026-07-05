import XCTest
@testable import ThreeMFKit

final class SmokeTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(ThreeMFKit.version.isEmpty)
    }
}

final class InternalDiagnosticsTests: XCTestCase {
    func testMatrixAndZipSelfTests() {
        let results = ThreeMFInternalDiagnostics.runSelfTests()
        XCTAssertFalse(results.isEmpty)
        for result in results {
            XCTAssertTrue(result.passed, "Self-test failed: \(result.name)")
        }
    }
}
