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

    private func sceneContainsCamera(_ node: SCNNode) -> Bool {
        if node.camera != nil { return true }
        return node.childNodes.contains { sceneContainsCamera($0) }
    }
}
#endif
