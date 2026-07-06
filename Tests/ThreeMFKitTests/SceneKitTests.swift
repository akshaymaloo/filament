import XCTest
@testable import ThreeMFKit
#if canImport(SceneKit)
import SceneKit
#endif

#if canImport(SceneKit)
final class SceneKitTests: XCTestCase {
    func testSceneConstructionOnly() throws {
        let data = ThreeMFFixtureFactory.minimalCube(deflate: false)
        let loader = ThreeMFLoader()
        let doc = try loader.load(data: data)
        let plate = try XCTUnwrap(doc.plates.first)

        let geometry = plate.mesh.makeGeometry()
        XCTAssertNotNil(geometry)

        let scene = plate.makeScene()
        let hasGeometryNode = scene.rootNode.childNodes.contains { node in
            node.childNodes.contains { $0.geometry != nil } || node.geometry != nil
        }
        XCTAssertTrue(hasGeometryNode)
        XCTAssertTrue(sceneContainsCamera(scene.rootNode))

        let camera3D = scene.previewCameraNode(for: .threeD)
        let camera2D = scene.previewCameraNode(for: .twoD)
        XCTAssertNotNil(camera3D)
        XCTAssertNotNil(camera2D)
        XCTAssertEqual(camera3D?.camera?.usesOrthographicProjection, false)
        XCTAssertEqual(camera2D?.camera?.usesOrthographicProjection, true)
    }

    /// Regression: the shadow ground plane must not use `SCNFloor` (its
    /// reflection "FloorPass" errors every frame and hangs Quick Look previews
    /// of large meshes) and must be single-sided (a double-sided plane occludes
    /// the model and greys out the view when the camera orbits below it).
    func testGroundPlaneIsNonOccludingPlane() throws {
        let doc = try ThreeMFLoader().load(data: ThreeMFFixtureFactory.minimalCube(deflate: false))
        let plate = try XCTUnwrap(doc.plates.first)
        let scene = plate.makeScene()

        var floorGeometries: [SCNGeometry] = []
        var usesSCNFloor = false
        forEachNode(scene.rootNode) { node in
            guard let geometry = node.geometry else { return }
            if geometry is SCNFloor { usesSCNFloor = true }
            // The model geometry has vertex data; the flat ground plane is an
            // SCNPlane. Collect planes to check their material.
            if geometry is SCNPlane { floorGeometries.append(geometry) }
        }

        XCTAssertFalse(usesSCNFloor, "SCNFloor causes a per-frame FloorPass render error; use SCNPlane")
        let floor = try XCTUnwrap(floorGeometries.first, "expected an SCNPlane ground/shadow catcher")
        let material = try XCTUnwrap(floor.firstMaterial)
        XCTAssertFalse(material.isDoubleSided, "ground plane must be single-sided so it doesn't occlude the model from below")
    }

    private func forEachNode(_ node: SCNNode, _ body: (SCNNode) -> Void) {
        body(node)
        for child in node.childNodes { forEachNode(child, body) }
    }

    private func sceneContainsCamera(_ node: SCNNode) -> Bool {
        if node.camera != nil { return true }
        return node.childNodes.contains { sceneContainsCamera($0) }
    }
}
#endif
