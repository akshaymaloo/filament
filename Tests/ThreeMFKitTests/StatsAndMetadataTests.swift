import XCTest
@testable import ThreeMFKit

final class StatsAndMetadataTests: XCTestCase {

    // MARK: - BambuPlateStatsParser.parseStats

    func testParseStatsFullObject() throws {
        let json = Data("""
        {"prediction": 3600, "weight": 12.5, "printer_model_id": "X1C",
         "filament_used_g": [10.0, 2.5], "filament_colors": ["#FF0000", "#00FF00"],
         "filament_types": ["PLA", "PETG"]}
        """.utf8)
        let stats = try XCTUnwrap(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
        XCTAssertEqual(stats.predictionSeconds, 3600)
        XCTAssertEqual(stats.weightGrams, 12.5)
        XCTAssertEqual(stats.printerModel, "X1C")
        XCTAssertEqual(stats.filaments.count, 2)
        XCTAssertEqual(stats.filaments[0].usedGrams, 10.0)
        XCTAssertEqual(stats.filaments[0].colorHex, "#FF0000")
        XCTAssertEqual(stats.filaments[0].type, "PLA")
        XCTAssertEqual(stats.filaments[1].usedGrams, 2.5)
        XCTAssertEqual(stats.filaments[1].colorHex, "#00FF00")
        XCTAssertEqual(stats.filaments[1].type, "PETG")
    }

    func testParseStatsFallsBackToMachineIdWhenNoPrinterModel() throws {
        let json = Data("""
        {"machine_id": "A1"}
        """.utf8)
        let stats = try XCTUnwrap(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
        XCTAssertEqual(stats.printerModel, "A1")
    }

    func testParseStatsUsesProjectLevelColorsAndTypesWhenPlateOmitsThem() throws {
        let json = Data("""
        {"prediction": 60, "filament_used_g": [5.0]}
        """.utf8)
        let stats = try XCTUnwrap(BambuPlateStatsParser.parseStats(json: json, colors: ["#0000FF"], types: ["ABS"]))
        XCTAssertEqual(stats.filaments.count, 1)
        XCTAssertEqual(stats.filaments[0].colorHex, "#0000FF")
        XCTAssertEqual(stats.filaments[0].type, "ABS")
    }

    func testParseStatsFallsBackToFilamentWeightKeyWhenUsedGMissing() throws {
        let json = Data("""
        {"filament_weight": [3.3, 4.4]}
        """.utf8)
        let stats = try XCTUnwrap(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
        XCTAssertEqual(stats.filaments.map(\.usedGrams), [3.3, 4.4])
    }

    func testParseStatsHandlesStringEncodedNumbers() throws {
        // Some slicer variants encode numeric fields as JSON strings.
        let json = Data("""
        {"prediction": "1800", "weight": "7.25"}
        """.utf8)
        let stats = try XCTUnwrap(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
        XCTAssertEqual(stats.predictionSeconds, 1800)
        XCTAssertEqual(stats.weightGrams, 7.25)
    }

    func testParseStatsMissingFieldsAreNilWithNoFilaments() throws {
        let json = Data("{}".utf8)
        let stats = try XCTUnwrap(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
        XCTAssertNil(stats.predictionSeconds)
        XCTAssertNil(stats.weightGrams)
        XCTAssertNil(stats.printerModel)
        XCTAssertTrue(stats.filaments.isEmpty)
    }

    func testParseStatsMalformedJSONReturnsNil() {
        let json = Data("not json".utf8)
        XCTAssertNil(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
    }

    func testParseStatsTopLevelArrayReturnsNil() {
        // Valid JSON, but not an object -- parser requires a top-level dictionary.
        let json = Data("[1, 2, 3]".utf8)
        XCTAssertNil(BambuPlateStatsParser.parseStats(json: json, colors: nil, types: nil))
    }

    // MARK: - BambuPlateStatsParser.parseProjectSettings

    func testParseProjectSettingsValid() {
        let json = Data("""
        {"filament_colour": ["#AA0000", "#00AA00"], "filament_type": ["PLA", "PLA"]}
        """.utf8)
        let parsed = BambuPlateStatsParser.parseProjectSettings(data: json)
        XCTAssertEqual(parsed.colors, ["#AA0000", "#00AA00"])
        XCTAssertEqual(parsed.types, ["PLA", "PLA"])
    }

    func testParseProjectSettingsMissingKeysReturnsNils() {
        let json = Data("{}".utf8)
        let parsed = BambuPlateStatsParser.parseProjectSettings(data: json)
        XCTAssertNil(parsed.colors)
        XCTAssertNil(parsed.types)
    }

    func testParseProjectSettingsMalformedJSONReturnsNils() {
        let json = Data("{not valid".utf8)
        let parsed = BambuPlateStatsParser.parseProjectSettings(data: json)
        XCTAssertNil(parsed.colors)
        XCTAssertNil(parsed.types)
    }

    // MARK: - OPCRelationships

    func testOPCRelationshipsParsesModelAndThumbnail() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/>
          <Relationship Id="rel-2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="/Metadata/thumbnail.png"/>
        </Relationships>
        """.utf8)
        let rels = try OPCRelationships.parse(data: xml)
        XCTAssertEqual(rels.modelPartPath, "3D/3dmodel.model")
        XCTAssertEqual(rels.thumbnailPartPath, "Metadata/thumbnail.png")
    }

    func testOPCRelationshipsNormalizesLeadingSlash() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="3D/3dmodel.model"/>
        </Relationships>
        """.utf8)
        let rels = try OPCRelationships.parse(data: xml)
        XCTAssertEqual(rels.modelPartPath, "3D/3dmodel.model")
    }

    func testOPCRelationshipsMissingThumbnailIsNil() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/3dmodel.model"/>
        </Relationships>
        """.utf8)
        let rels = try OPCRelationships.parse(data: xml)
        XCTAssertNil(rels.thumbnailPartPath)
    }

    func testOPCRelationshipsIgnoresUnknownRelationshipTypes() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://example.com/some/other/type" Target="/Foo/bar.xml"/>
        </Relationships>
        """.utf8)
        let rels = try OPCRelationships.parse(data: xml)
        XCTAssertNil(rels.modelPartPath)
        XCTAssertNil(rels.thumbnailPartPath)
    }

    func testOPCRelationshipsDuplicateTypeLastWins() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/first.model"/>
          <Relationship Id="rel-2" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" Target="/3D/second.model"/>
        </Relationships>
        """.utf8)
        let rels = try OPCRelationships.parse(data: xml)
        XCTAssertEqual(rels.modelPartPath, "3D/second.model")
    }

    func testOPCRelationshipsMalformedXMLThrows() {
        let xml = Data("<Relationships><Relationship".utf8)
        XCTAssertThrowsError(try OPCRelationships.parse(data: xml)) { error in
            guard case ThreeMFError.malformedXML = error else {
                return XCTFail("Expected malformedXML, got \(error)")
            }
        }
    }

    func testOPCRelationshipsEmptyRelationshipsIsEmpty() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
        """.utf8)
        let rels = try OPCRelationships.parse(data: xml)
        XCTAssertNil(rels.modelPartPath)
        XCTAssertNil(rels.thumbnailPartPath)
    }

    // MARK: - LengthUnit

    func testLengthUnitMillimetersPerUnit() {
        XCTAssertEqual(LengthUnit.micron.millimetersPerUnit, 0.001)
        XCTAssertEqual(LengthUnit.millimeter.millimetersPerUnit, 1)
        XCTAssertEqual(LengthUnit.centimeter.millimetersPerUnit, 10)
        XCTAssertEqual(LengthUnit.inch.millimetersPerUnit, 25.4)
        XCTAssertEqual(LengthUnit.foot.millimetersPerUnit, 304.8)
        XCTAssertEqual(LengthUnit.meter.millimetersPerUnit, 1000)
    }

    func testLengthUnitRawValueRoundTrip() {
        for unit: LengthUnit in [.micron, .millimeter, .centimeter, .inch, .foot, .meter] {
            XCTAssertEqual(LengthUnit(rawValue: unit.rawValue), unit)
        }
    }

    func testLengthUnitUnknownRawValueIsNil() {
        XCTAssertNil(LengthUnit(rawValue: "parsec"))
    }

    // MARK: - ThreeMFError

    func testEveryErrorCaseHasNonEmptyDescription() {
        let cases: [ThreeMFError] = [
            .notAZipArchive,
            .missingModelPart,
            .malformedXML("detail"),
            .entryTooLarge(path: "3D/3dmodel.model", size: 100, limit: 10),
            .unsupportedCompression(method: 99),
            .corruptArchive("detail"),
            .malformedMesh("detail"),
            .meshTooLarge(triangles: 100, limit: 10),
            .cancelled,
            .archiveTooLarge(limit: 10)
        ]
        for error in cases {
            XCTAssertFalse(error.description.isEmpty, "\(error) has an empty description")
        }
    }

    func testErrorDescriptionsIncludeRelevantDetails() {
        XCTAssertTrue(ThreeMFError.malformedXML("boom").description.contains("boom"))
        XCTAssertTrue(ThreeMFError.entryTooLarge(path: "foo.xml", size: 5, limit: 1).description.contains("foo.xml"))
        XCTAssertTrue(ThreeMFError.entryTooLarge(path: "foo.xml", size: 5, limit: 1).description.contains("5"))
        XCTAssertTrue(ThreeMFError.unsupportedCompression(method: 12).description.contains("12"))
        XCTAssertTrue(ThreeMFError.corruptArchive("bad").description.contains("bad"))
        XCTAssertTrue(ThreeMFError.malformedMesh("bad mesh").description.contains("bad mesh"))
        XCTAssertTrue(ThreeMFError.meshTooLarge(triangles: 500, limit: 100).description.contains("500"))
        XCTAssertTrue(ThreeMFError.archiveTooLarge(limit: 42).description.contains("42"))
    }
}
