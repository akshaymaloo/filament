import XCTest
@testable import ThreeMFKit
#if canImport(SceneKit)
import SceneKit
#endif

final class PaintColorDecoderTests: XCTestCase {
    func testDecodeKnownPaintedExtruder() {
        // "8" is the shortest hex bitstream that decodes to extruder 2: its
        // single nibble read LSB-first gives bits [0,0,0,1] — the first two
        // bits are `nss=0` (leaf), the next two are `sc=2` (`sc < 3`, so
        // `state = sc = 2`), i.e. "painted with extruder 2".
        XCTAssertEqual(PaintColorDecoder.decode("8"), 2)
    }

    func testDecodeEmptyIsUnpainted() {
        XCTAssertEqual(PaintColorDecoder.decode(""), 0)
    }

    func testDecodeAnotherKnownValue() {
        // Same reasoning as above with nibble "4" (bits [0,0,1,0]): `nss=0`,
        // `sc=1` -> state 1 (extruder 1).
        XCTAssertEqual(PaintColorDecoder.decode("4"), 1)
    }
}

final class BambuPaintedTrianglesTests: XCTestCase {
    func testLoadPaletteAndColorIndices() throws {
        let data = ThreeMFFixtureFactory.bambuPaintedTriangles()
        let doc = try ThreeMFLoader().load(data: data)

        XCTAssertEqual(doc.plates.count, 1)
        let plate = try XCTUnwrap(doc.plates.first)

        XCTAssertEqual(plate.palette, ["#FF0000", "#00FF00"])
        XCTAssertEqual(plate.mesh.triangleCount, 12)

        let colorIndices = try XCTUnwrap(plate.mesh.triangleColorIndices)
        XCTAssertEqual(colorIndices.count, plate.mesh.triangleCount)
        XCTAssertTrue(colorIndices.contains(0), "expected at least one triangle at the base extruder (red)")
        XCTAssertTrue(colorIndices.contains(1), "expected at least one painted triangle (green)")
    }

    func testPlainFixtureHasNoColorIndices() throws {
        // A plain (non-Bambu) 3MF has no paint data and no palette, so the
        // merged mesh should stay uncolored (nil), rendering neutral.
        let data = ThreeMFFixtureFactory.minimalCube(deflate: false)
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)

        XCTAssertTrue(plate.palette.isEmpty)
        XCTAssertNil(plate.mesh.triangleColorIndices)
    }

#if canImport(SceneKit)
    func testMakeSceneProducesMultipleColorMaterials() throws {
        let data = ThreeMFFixtureFactory.bambuPaintedTriangles()
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)

        let scene = plate.makeScene()
        var diffuseColors: Set<NSColor> = []
        forEachNode(scene.rootNode) { node in
            guard let geometry = node.geometry else { return }
            for material in geometry.materials {
                if let color = material.diffuse.contents as? NSColor {
                    diffuseColors.insert(color)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(diffuseColors.count, 2, "expected one material per distinct filament color")
    }

    func testUseModelColorsFalseFallsBackToNeutral() throws {
        let data = ThreeMFFixtureFactory.bambuPaintedTriangles()
        let doc = try ThreeMFLoader().load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)

        var style = PreviewStyle.default
        style.useModelColors = false
        let scene = plate.makeScene(style: style)

        var diffuseColors: Set<NSColor> = []
        forEachNode(scene.rootNode) { node in
            guard let geometry = node.geometry, !(geometry is SCNPlane) else { return }
            for material in geometry.materials {
                if let color = material.diffuse.contents as? NSColor {
                    diffuseColors.insert(color)
                }
            }
        }
        XCTAssertEqual(diffuseColors.count, 1, "useModelColors == false should render a single neutral material")
    }

    private func forEachNode(_ node: SCNNode, _ body: (SCNNode) -> Void) {
        body(node)
        for child in node.childNodes { forEachNode(child, body) }
    }
#endif
}
