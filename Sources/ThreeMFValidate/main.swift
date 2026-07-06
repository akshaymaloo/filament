import Foundation
import ThreeMFKit
#if canImport(SceneKit)
import SceneKit
#endif

var failureCount = 0
var checkCount = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    checkCount += 1
    let passed = condition()
    if passed {
        print("✓ \(name)")
    } else {
        failureCount += 1
        print("✗ \(name)")
    }
}

func run(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
    } catch {
        failureCount += 1
        checkCount += 1
        print("✗ \(name) threw: \(error)")
    }
}

func isPNG(_ data: Data) -> Bool {
    let signature: [UInt8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
    guard data.count >= 8 else { return false }
    return Array(data.prefix(8)) == signature
}

#if canImport(SceneKit)
func sceneContainsCamera(_ node: SCNNode) -> Bool {
    if node.camera != nil { return true }
    return node.childNodes.contains { sceneContainsCamera($0) }
}

func forEachNode(_ node: SCNNode, _ body: (SCNNode) -> Void) {
    body(node)
    for child in node.childNodes { forEachNode(child, body) }
}
#endif

print("ThreeMFKit \(ThreeMFKit.version) validation suite")
print("========================================")

// MARK: - Internal diagnostics (Matrix4 transform math, ZIP writer/reader round-trip)

for result in ThreeMFInternalDiagnostics.runSelfTests() {
    check(result.name, result.passed)
}

// MARK: - minimalCube (STORE and DEFLATE)

for deflate in [false, true] {
    let label = deflate ? "deflate" : "store"
    run("minimalCube(\(label)) load") {
        let data = ThreeMFFixtureFactory.minimalCube(deflate: deflate)
        let loader = ThreeMFLoader()
        let doc = try loader.load(data: data)

        check("[\(label)] unit == millimeter", doc.unit == .millimeter)
        check("[\(label)] exactly 1 plate", doc.plates.count == 1)
        guard let plate = doc.plates.first else { return }
        check("[\(label)] plate id == 1", plate.id == 1)
        check("[\(label)] mesh triangleCount == 12", plate.mesh.triangleCount == 12)
        check("[\(label)] mesh positions count == 8", plate.mesh.positions.count == 8)

        if let bbox = plate.mesh.boundingBox {
            check("[\(label)] bounding box min == (0,0,0)", bbox.min == SIMD3<Float>(0, 0, 0))
            check("[\(label)] bounding box max == (20,20,20)", bbox.max == SIMD3<Float>(20, 20, 20))
        } else {
            check("[\(label)] bounding box present", false)
        }

        check("[\(label)] no package thumbnail", doc.packageThumbnail == nil)
        check("[\(label)] no primary thumbnail", doc.primaryThumbnail == nil)
    }
}

// MARK: - translatedComponent

run("translatedComponent load") {
    let data = ThreeMFFixtureFactory.translatedComponent()
    let loader = ThreeMFLoader()
    let doc = try loader.load(data: data)

    check("translatedComponent: 1 plate", doc.plates.count == 1)
    guard let plate = doc.plates.first else { return }
    check("translatedComponent: triangleCount == 12", plate.mesh.triangleCount == 12)
    if let bbox = plate.mesh.boundingBox {
        check("translatedComponent: bbox min == (10,20,30)", bbox.min == SIMD3<Float>(10, 20, 30))
        check("translatedComponent: bbox max == (30,40,50)", bbox.max == SIMD3<Float>(30, 40, 50))
    } else {
        check("translatedComponent: bounding box present", false)
    }
}

// MARK: - productionExtensionCube (3MF Production Extension, cross-part component)

run("productionExtensionCube load") {
    let data = ThreeMFFixtureFactory.productionExtensionCube()
    let loader = ThreeMFLoader()
    let doc = try loader.load(data: data)

    check("productionExtensionCube: 1 plate", doc.plates.count == 1)
    guard let plate = doc.plates.first else { return }
    check("productionExtensionCube: triangleCount == 12", plate.mesh.triangleCount == 12)
    if let bbox = plate.mesh.boundingBox {
        check("productionExtensionCube: bbox min == (0,0,0)", bbox.min == SIMD3<Float>(0, 0, 0))
        check("productionExtensionCube: bbox max == (20,20,20)", bbox.max == SIMD3<Float>(20, 20, 20))
    } else {
        check("productionExtensionCube: bounding box present", false)
    }
}

// MARK: - bambuTwoPlates

run("bambuTwoPlates load") {
    let data = ThreeMFFixtureFactory.bambuTwoPlates()
    let loader = ThreeMFLoader()
    let doc = try loader.load(data: data)

    check("bambuTwoPlates: 2 plates", doc.plates.count == 2)
    check("bambuTwoPlates: ids == [1,2]", doc.plates.map { $0.id } == [1, 2])

    if let plate1 = doc.plates.first(where: { $0.id == 1 }) {
        check("bambuTwoPlates: plate 1 name == 'Cube A'", plate1.name == "Cube A")
        check("bambuTwoPlates: plate 1 thumbnail present", plate1.thumbnail != nil)
        check("bambuTwoPlates: plate 1 thumbnail is PNG", plate1.thumbnail.map(isPNG) ?? false)
        check("bambuTwoPlates: plate 1 stats present", plate1.stats != nil)
        check("bambuTwoPlates: plate 1 predictionSeconds == 3600", plate1.stats?.predictionSeconds == 3600)
        check("bambuTwoPlates: plate 1 weightGrams == 12.5", plate1.stats?.weightGrams == 12.5)
        check("bambuTwoPlates: plate 1 mesh triangleCount == 12", plate1.mesh.triangleCount == 12)
    } else {
        check("bambuTwoPlates: plate 1 exists", false)
    }

    if let plate2 = doc.plates.first(where: { $0.id == 2 }) {
        check("bambuTwoPlates: plate 2 name == 'Plate 2' (empty plater_name fallback)", plate2.name == "Plate 2")
        check("bambuTwoPlates: plate 2 mesh triangleCount == 12", plate2.mesh.triangleCount == 12)
    } else {
        check("bambuTwoPlates: plate 2 exists", false)
    }

    check("bambuTwoPlates: packageThumbnail present", doc.packageThumbnail != nil)
    check("bambuTwoPlates: primaryThumbnail present", doc.primaryThumbnail != nil)

    let quickThumb = try loader.extractPrimaryThumbnail(data: data)
    check("bambuTwoPlates: extractPrimaryThumbnail non-nil", quickThumb != nil)
    check("bambuTwoPlates: extractPrimaryThumbnail is PNG", quickThumb.map(isPNG) ?? false)
}

// MARK: - bambuPaintedTriangles (multi-color paint_color + filament palette)

run("bambuPaintedTriangles load") {
    let data = ThreeMFFixtureFactory.bambuPaintedTriangles()
    let loader = ThreeMFLoader()
    let doc = try loader.load(data: data)

    check("bambuPaintedTriangles: 1 plate", doc.plates.count == 1)
    guard let plate = doc.plates.first else { return }

    check("bambuPaintedTriangles: palette == [#FF0000, #00FF00]", plate.palette == ["#FF0000", "#00FF00"])
    check("bambuPaintedTriangles: mesh triangleCount == 12", plate.mesh.triangleCount == 12)

    guard let colorIndices = plate.mesh.triangleColorIndices else {
        check("bambuPaintedTriangles: triangleColorIndices non-nil", false)
        return
    }
    check("bambuPaintedTriangles: triangleColorIndices non-nil", true)
    check("bambuPaintedTriangles: triangleColorIndices count == triangleCount", colorIndices.count == plate.mesh.triangleCount)
    check("bambuPaintedTriangles: at least one triangle at palette index 1 (green, painted)", colorIndices.contains(1))
    check("bambuPaintedTriangles: at least one triangle at palette index 0 (red, base extruder)", colorIndices.contains(0))
}

run("PaintColorDecoder known values") {
    check("PaintColorDecoder.decode(\"8\") == 2", PaintColorDecoder.decode("8") == 2)
    check("PaintColorDecoder.decode(\"\") == 0", PaintColorDecoder.decode("") == 0)
}

#if canImport(SceneKit)
run("SceneKit multi-color scene construction") {
    let data = ThreeMFFixtureFactory.bambuPaintedTriangles()
    let loader = ThreeMFLoader()
    let doc = try loader.load(data: data)
    guard let plate = doc.plates.first else {
        check("SceneKit colored: plate available", false)
        return
    }

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
    check("SceneKit colored: scene has >= 2 distinct diffuse materials", diffuseColors.count >= 2)
}
#endif

// MARK: - Thumbnail-only fast path (parseMesh = false)

run("thumbnailOnly options fast path") {
    let data = ThreeMFFixtureFactory.bambuTwoPlates()
    let loader = ThreeMFLoader(options: .thumbnailOnly)
    let doc = try loader.load(data: data)
    check("thumbnailOnly: still enumerates 2 plates", doc.plates.count == 2)
    check("thumbnailOnly: meshes are empty", doc.plates.allSatisfy { $0.mesh.isEmpty })
    check("thumbnailOnly: plate 1 thumbnail still present", doc.plates.first(where: { $0.id == 1 })?.thumbnail != nil)
}

// MARK: - SceneKit (construction only, no rendering)

#if canImport(SceneKit)
run("SceneKit scene construction") {
    let data = ThreeMFFixtureFactory.minimalCube(deflate: false)
    let loader = ThreeMFLoader()
    let doc = try loader.load(data: data)
    guard let plate = doc.plates.first else {
        check("SceneKit: plate available", false)
        return
    }
    let geometry = plate.mesh.makeGeometry()
    check("SceneKit: makeGeometry() non-nil for cube", geometry != nil)

    let scene = plate.makeScene()
    let hasGeometryNode = scene.rootNode.childNodes.contains { node in
        node.childNodes.contains { $0.geometry != nil } || node.geometry != nil
    }
    check("SceneKit: makeScene() contains a geometry node", hasGeometryNode)
    check("SceneKit: makeScene() contains a camera node", sceneContainsCamera(scene.rootNode))

    let camera3D = scene.previewCameraNode
    check("SceneKit: previewCameraNode non-nil", camera3D != nil)
    check(
        "SceneKit: previewCameraNode uses perspective projection",
        camera3D?.camera?.usesOrthographicProjection == false
    )

    // The default style is shadow-free: no ground plane should be added.
    var defaultHasPlane = false
    forEachNode(scene.rootNode) { node in
        if node.geometry is SCNPlane { defaultHasPlane = true }
    }
    check("SceneKit: default style has no ground plane (shadow-free)", !defaultHasPlane)

    // Regression checks for the opt-in grounded style: the ground/shadow plane
    // must not use SCNFloor (its reflection pass errors every frame and hangs
    // previews of large meshes), and must be single-sided (a double-sided plane
    // greys out the model when the camera orbits below it).
    var groundedStyle = PreviewStyle.studio(useModelColors: false, isDark: false)
    groundedStyle.showGroundPlane = true
    groundedStyle.enableShadows = true
    let groundedScene = plate.makeScene(style: groundedStyle)
    var usesSCNFloor = false
    var planeMaterial: SCNMaterial? = nil
    forEachNode(groundedScene.rootNode) { node in
        guard let geometry = node.geometry else { return }
        if geometry is SCNFloor { usesSCNFloor = true }
        if geometry is SCNPlane, planeMaterial == nil { planeMaterial = geometry.firstMaterial }
    }
    check("SceneKit: does not use SCNFloor (avoids FloorPass hang)", !usesSCNFloor)
    check("SceneKit: grounded style ground plane exists", planeMaterial != nil)
    check("SceneKit: ground plane is single-sided (no occlusion from below)", planeMaterial?.isDoubleSided == false)
}
#endif

// MARK: - Error handling

run("error handling for malformed/empty data") {
    let loader = ThreeMFLoader()
    do {
        _ = try loader.load(data: Data("not a zip".utf8))
        check("malformed data throws", false)
    } catch {
        check("malformed data throws", true)
    }
}

// MARK: - STL / OBJ / PLY mesh format fixtures

func checkModelDocument(_ label: String, doc: ThreeMFDocument, expectedName: String) {
    check("\(label): unit == millimeter", doc.unit == .millimeter)
    check("\(label): exactly 1 plate", doc.plates.count == 1)
    guard let plate = doc.plates.first else { return }
    check("\(label): mesh triangleCount == 12", plate.mesh.triangleCount == 12)
    check("\(label): plate name == '\(expectedName)'", plate.name == expectedName)
    if let bbox = plate.mesh.boundingBox {
        check("\(label): bounding box min == (0,0,0)", bbox.min == SIMD3<Float>(0, 0, 0))
        check("\(label): bounding box max == (20,20,20)", bbox.max == SIMD3<Float>(20, 20, 20))
    } else {
        check("\(label): bounding box present", false)
    }
}

let modelLoader = ModelLoader()

run("STL binary cube load") {
    let data = ThreeMFFixtureFactory.stlBinaryCube()
    let doc = try modelLoader.load(data: data, format: .stl, name: "stl-binary-cube")
    checkModelDocument("STL binary cube", doc: doc, expectedName: "stl-binary-cube")
}

run("STL ascii cube load") {
    let data = ThreeMFFixtureFactory.stlASCIICube()
    let doc = try modelLoader.load(data: data, format: .stl, name: "stl-ascii-cube")
    checkModelDocument("STL ascii cube", doc: doc, expectedName: "stl-ascii-cube")
}

run("OBJ cube load") {
    let data = ThreeMFFixtureFactory.objCube()
    let doc = try modelLoader.load(data: data, format: .obj, name: "obj-cube")
    checkModelDocument("OBJ cube", doc: doc, expectedName: "obj-cube")
}

run("PLY ascii cube load") {
    let data = ThreeMFFixtureFactory.plyASCIICube()
    let doc = try modelLoader.load(data: data, format: .ply, name: "ply-ascii-cube")
    checkModelDocument("PLY ascii cube", doc: doc, expectedName: "ply-ascii-cube")
}

run("PLY binary little-endian cube load") {
    let data = ThreeMFFixtureFactory.plyBinaryLECube()
    let doc = try modelLoader.load(data: data, format: .ply, name: "ply-binary-le-cube")
    checkModelDocument("PLY binary LE cube", doc: doc, expectedName: "ply-binary-le-cube")
}

run("PLY binary big-endian cube load") {
    let data = ThreeMFFixtureFactory.plyBinaryBECube()
    let doc = try modelLoader.load(data: data, format: .ply, name: "ply-binary-be-cube")
    checkModelDocument("PLY binary BE cube", doc: doc, expectedName: "ply-binary-be-cube")
}

// MARK: - ModelFormat lookup

check("ModelFormat(fileExtension: \"STL\") == .stl", ModelFormat(fileExtension: "STL") == .stl)
check("ModelFormat(fileExtension: \".obj\") == .obj", ModelFormat(fileExtension: ".obj") == .obj)
check("ModelFormat(fileExtension: \"PLY\") == .ply", ModelFormat(fileExtension: "PLY") == .ply)
check("ModelFormat(fileExtension: \"3mf\") == .threeMF", ModelFormat(fileExtension: "3mf") == .threeMF)
check("ModelFormat(fileExtension: \"xyz\") == nil", ModelFormat(fileExtension: "xyz") == nil)
check("ModelFormat.supportedExtensions == [3mf, stl, obj, ply]", ModelFormat.supportedExtensions == ["3mf", "stl", "obj", "ply"])

// MARK: - ModelLoader.load(url:) extension dispatch

run("ModelLoader.load(url:) dispatches by extension") {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ThreeMFKitValidate-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let fileURL = tempDir.appendingPathComponent("my-cube.stl")
    try ThreeMFFixtureFactory.stlBinaryCube().write(to: fileURL)

    let doc = try modelLoader.load(url: fileURL)
    checkModelDocument("ModelLoader.load(url:) STL", doc: doc, expectedName: "my-cube")
}

print("========================================")
print("\(checkCount - failureCount)/\(checkCount) checks passed")
if failureCount > 0 {
    print("FAILED: \(failureCount) check(s) did not pass.")
    exit(1)
} else {
    print("All checks passed.")
    exit(0)
}
