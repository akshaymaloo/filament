import XCTest
@testable import FilamentKit
import FilamentTestSupport

final class SmokeTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(FilamentKit.version.isEmpty)
    }
}

final class InternalDiagnosticsTests: XCTestCase {
    func testMatrixAndZipSelfTests() {
        let results = FilamentInternalDiagnostics.runSelfTests()
        XCTAssertFalse(results.isEmpty)
        for result in results {
            XCTAssertTrue(result.passed, "Self-test failed: \(result.name)")
        }
    }
}
