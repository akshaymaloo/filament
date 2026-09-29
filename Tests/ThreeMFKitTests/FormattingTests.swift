import XCTest
@testable import ThreeMFKit

final class FormattingTests: XCTestCase {

    // MARK: - duration

    func testDurationZeroSeconds() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 0), "0m")
    }

    func testDurationJustUnderAMinuteRoundsDown() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 59), "0m")
    }

    func testDurationExactlyOneMinute() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 60), "1m")
    }

    func testDurationJustUnderAnHour() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 3599), "59m")
    }

    func testDurationExactlyOneHour() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 3600), "1h 0m")
    }

    func testDurationOneHourOneMinuteOneSecond() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 3661), "1h 1m")
    }

    func testDurationManyHours() {
        // 90061s = 25h 1m 1s
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: 90061), "25h 1m")
    }

    func testDurationNegativeClampsToZero() {
        XCTAssertEqual(PrintStatsFormatting.duration(seconds: -100), "0m")
    }

    // MARK: - weight

    func testWeightRoundsToOneDecimal() {
        XCTAssertEqual(PrintStatsFormatting.weight(grams: 12.34), "12.3 g")
        XCTAssertEqual(PrintStatsFormatting.weight(grams: 12.36), "12.4 g")
        XCTAssertEqual(PrintStatsFormatting.weight(grams: 0), "0.0 g")
    }

    // MARK: - dimensions

    private func cubeMesh() -> TriangleMesh {
        TriangleMesh(
            positions: [
                SIMD3<Float>(0, 0, 0),
                SIMD3<Float>(2, 3, 4)
            ],
            indices: [0, 0, 1] // enough for a bounding box; not a valid render but dimensions() only needs positions
        )
    }

    func testDimensionsMillimeter() throws {
        let dims = try XCTUnwrap(PrintStatsFormatting.dimensions(for: cubeMesh(), unit: .millimeter))
        XCTAssertEqual(dims, "2.0 × 3.0 × 4.0 mm")
    }

    func testDimensionsCentimeter() throws {
        let dims = try XCTUnwrap(PrintStatsFormatting.dimensions(for: cubeMesh(), unit: .centimeter))
        XCTAssertEqual(dims, "20.0 × 30.0 × 40.0 mm")
    }

    func testDimensionsInch() throws {
        let dims = try XCTUnwrap(PrintStatsFormatting.dimensions(for: cubeMesh(), unit: .inch))
        XCTAssertEqual(dims, "50.8 × 76.2 × 101.6 mm")
    }

    func testDimensionsMicron() throws {
        let dims = try XCTUnwrap(PrintStatsFormatting.dimensions(for: cubeMesh(), unit: .micron))
        XCTAssertEqual(dims, "0.0 × 0.0 × 0.0 mm")
    }

    func testDimensionsMeter() throws {
        let dims = try XCTUnwrap(PrintStatsFormatting.dimensions(for: cubeMesh(), unit: .meter))
        XCTAssertEqual(dims, "2000.0 × 3000.0 × 4000.0 mm")
    }

    func testDimensionsFoot() throws {
        let dims = try XCTUnwrap(PrintStatsFormatting.dimensions(for: cubeMesh(), unit: .foot))
        XCTAssertEqual(dims, "609.6 × 914.4 × 1219.2 mm")
    }

    func testDimensionsNilForEmptyMesh() {
        XCTAssertNil(PrintStatsFormatting.dimensions(for: TriangleMesh(), unit: .millimeter))
    }

    // MARK: - triangleCount

    func testTriangleCountZeroIsPlural() {
        XCTAssertEqual(PrintStatsFormatting.triangleCount(0), "0 triangles")
    }

    func testTriangleCountOneIsSingular() {
        XCTAssertEqual(PrintStatsFormatting.triangleCount(1), "1 triangle")
    }

    func testTriangleCountTwoIsPlural() {
        XCTAssertEqual(PrintStatsFormatting.triangleCount(2), "2 triangles")
    }

    func testTriangleCountNoGroupingBelowThousand() {
        XCTAssertEqual(PrintStatsFormatting.triangleCount(999), "999 triangles")
    }

    func testTriangleCountGroupingAtThousand() {
        XCTAssertEqual(PrintStatsFormatting.triangleCount(1000), "1,000 triangles")
    }

    func testTriangleCountGroupingLargeNumber() {
        XCTAssertEqual(PrintStatsFormatting.triangleCount(1234567), "1,234,567 triangles")
    }

    // MARK: - rgba

    func testRGBAValidSixDigit() throws {
        let rgba = try XCTUnwrap(PrintStatsFormatting.rgba(fromHex: "FF0080"))
        XCTAssertEqual(rgba.red, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.green, 0.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.blue, 128.0 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.alpha, 1.0, accuracy: 1e-9)
    }

    func testRGBAValidEightDigitWithAlpha() throws {
        let rgba = try XCTUnwrap(PrintStatsFormatting.rgba(fromHex: "112233CC"))
        XCTAssertEqual(rgba.red, 0x11 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.green, 0x22 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.blue, 0x33 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.alpha, 0xCC / 255.0, accuracy: 1e-9)
    }

    func testRGBAHandlesLeadingHash() throws {
        let rgba = try XCTUnwrap(PrintStatsFormatting.rgba(fromHex: "#00FF00"))
        XCTAssertEqual(rgba.red, 0.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.green, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.blue, 0.0, accuracy: 1e-9)
    }

    func testRGBATrimsWhitespace() throws {
        let rgba = try XCTUnwrap(PrintStatsFormatting.rgba(fromHex: "  #0000FF \n"))
        XCTAssertEqual(rgba.blue, 1.0, accuracy: 1e-9)
    }

    func testRGBAAcceptsLowercase() throws {
        let rgba = try XCTUnwrap(PrintStatsFormatting.rgba(fromHex: "#ff00aa"))
        XCTAssertEqual(rgba.red, 1.0, accuracy: 1e-9)
        XCTAssertEqual(rgba.blue, 0xAA / 255.0, accuracy: 1e-9)
    }

    func testRGBAInvalidLengthReturnsNil() {
        XCTAssertNil(PrintStatsFormatting.rgba(fromHex: "#FFF"))
        XCTAssertNil(PrintStatsFormatting.rgba(fromHex: "#FF00"))
        XCTAssertNil(PrintStatsFormatting.rgba(fromHex: "#FF00000"))
    }

    func testRGBAInvalidCharactersReturnsNil() {
        XCTAssertNil(PrintStatsFormatting.rgba(fromHex: "#GGGGGG"))
        XCTAssertNil(PrintStatsFormatting.rgba(fromHex: "#ZZ0000"))
    }

    func testRGBANilInputReturnsNil() {
        XCTAssertNil(PrintStatsFormatting.rgba(fromHex: nil))
    }
}
