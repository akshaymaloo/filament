import XCTest
@testable import ThreeMFKit

/// Exercises the hand-written byte-scanner `ModelXMLParser` on the tricky bits
/// of real-world 3MF model XML: exponent-notation floats, single-quoted
/// attributes, namespaced Production Extension `p:path`, self-closing vs.
/// explicitly-closed elements, and per-triangle `paint_color`.
final class ModelXMLParserTests: XCTestCase {
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <model unit="millimeter" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
      <resources>
        <object id="1" type="model">
          <mesh>
            <vertices>
              <vertex x="0" y="0" z="0"/>
              <vertex x='1.5e1' y="2E-1" z="-3.25"/>
              <vertex x="10" y="10" z="10"></vertex>
            </vertices>
            <triangles>
              <triangle v1="0" v2="1" v3="2" paint_color="8"/>
              <triangle v1="2" v2="1" v3="0" />
            </triangles>
          </mesh>
        </object>
        <object id="2">
          <components>
            <component objectid="1" transform="1 0 0 0 1 0 0 0 1 5 0 0" p:path="/3D/Objects/part.model"/>
          </components>
        </object>
      </resources>
      <build>
        <item objectid="2" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
      </build>
    </model>
    """

    func testParsesGeometryAttributesAndNumbers() throws {
        let parser = try ModelXMLParser.parse(data: Data(sample.utf8), parseMesh: true)

        XCTAssertEqual(parser.unit, .millimeter)

        guard case let .mesh(mesh, paintStates)? = parser.objects[1] else {
            return XCTFail("object 1 should be a mesh")
        }

        // Vertices, including exponent and single-quoted values.
        XCTAssertEqual(mesh.positions.count, 3)
        XCTAssertEqual(mesh.positions[0], SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(mesh.positions[1].x, 15, accuracy: 1e-4)  // 1.5e1
        XCTAssertEqual(mesh.positions[1].y, 0.2, accuracy: 1e-4) // 2E-1
        XCTAssertEqual(mesh.positions[1].z, -3.25, accuracy: 1e-4)
        XCTAssertEqual(mesh.positions[2], SIMD3<Float>(10, 10, 10))

        // Triangles (both self-closing and space-before-slash forms).
        XCTAssertEqual(mesh.indices, [0, 1, 2, 2, 1, 0])

        // paint_color present on the first triangle, absent on the second.
        XCTAssertEqual(paintStates.count, 2)
        XCTAssertEqual(paintStates[0], PaintColorDecoder.decode("8"))
        XCTAssertGreaterThan(paintStates[0], 0)
        XCTAssertEqual(paintStates[1], 0)
    }

    func testParsesNamespacedComponentPathAndBuildItems() throws {
        let parser = try ModelXMLParser.parse(data: Data(sample.utf8), parseMesh: true)

        guard case let .components(components)? = parser.objects[2] else {
            return XCTFail("object 2 should be components")
        }
        XCTAssertEqual(components.count, 1)
        XCTAssertEqual(components[0].objectId, 1)
        XCTAssertEqual(components[0].path, "/3D/Objects/part.model")

        XCTAssertEqual(parser.buildItems.count, 1)
        XCTAssertEqual(parser.buildItems[0].objectId, 2)
    }

    func testParseMeshFalseSkipsGeometry() throws {
        let parser = try ModelXMLParser.parse(data: Data(sample.utf8), parseMesh: false)

        guard case let .mesh(mesh, paintStates)? = parser.objects[1] else {
            return XCTFail("object 1 should still be a (empty) mesh")
        }
        XCTAssertTrue(mesh.positions.isEmpty)
        XCTAssertTrue(mesh.indices.isEmpty)
        XCTAssertTrue(paintStates.isEmpty)
        // Structure (components / build items) is still parsed.
        XCTAssertEqual(parser.buildItems.count, 1)
    }
}
