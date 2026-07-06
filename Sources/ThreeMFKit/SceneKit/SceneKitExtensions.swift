#if canImport(SceneKit)
import SceneKit
import simd
#if canImport(AppKit)
import AppKit
#endif

/// Which camera a host should use for `SCNScene.previewCameraNode(for:)`.
public enum PreviewCameraMode {
    /// Perspective, isometric-ish camera named `"camera3D"`.
    case threeD
    /// Orthographic, front elevation camera named `"camera2D"`.
    case twoD
}

public extension SCNScene {
    /// Returns the named camera node (`"camera3D"` / `"camera2D"`) added by
    /// `BuildPlate.makeScene(style:)`, if present.
    func previewCameraNode(for mode: PreviewCameraMode) -> SCNNode? {
        let name: String
        switch mode {
        case .threeD: name = "camera3D"
        case .twoD: name = "camera2D"
        }
        return rootNode.childNode(withName: name, recursively: true)
    }
}

public extension TriangleMesh {
    /// Builds an `SCNGeometry` from this mesh's positions/indices with smooth
    /// per-vertex normals. Returns `nil` for an empty mesh.
    func makeGeometry() -> SCNGeometry? {
        guard !isEmpty else { return nil }

        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var triangleIndex = 0
        while triangleIndex + 2 < indices.count {
            let i0 = Int(indices[triangleIndex])
            let i1 = Int(indices[triangleIndex + 1])
            let i2 = Int(indices[triangleIndex + 2])
            triangleIndex += 3
            guard i0 < positions.count, i1 < positions.count, i2 < positions.count else { continue }
            let v0 = positions[i0], v1 = positions[i1], v2 = positions[i2]
            let faceNormal = simd_cross(v1 - v0, v2 - v0)
            normals[i0] += faceNormal
            normals[i1] += faceNormal
            normals[i2] += faceNormal
        }
        let smoothed = normals.map { n -> SIMD3<Float> in
            let len = simd_length(n)
            return len > 0 ? n / len : SIMD3<Float>(0, 0, 1)
        }

        let positionSource = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let normalSource = SCNGeometrySource(normals: smoothed.map { SCNVector3($0.x, $0.y, $0.z) })

        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: triangleCount,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        return SCNGeometry(sources: [positionSource, normalSource], elements: [element])
    }
}

public extension BuildPlate {
    /// Builds a scene containing this plate's mesh (upright, Z-up rotated into
    /// SceneKit's Y-up space), a pair of named cameras (perspective "camera3D"
    /// and front-elevation orthographic "camera2D"), and soft studio lighting
    /// with an optional ground-contact shadow and image-based environment
    /// reflections.
    /// Construction only — no offscreen rendering is performed.
    func makeScene(style: PreviewStyle = .default) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = style.backgroundColor

        // 3D-printing content is authored Z-up; SceneKit is Y-up.
        let uprightRoot = SCNNode()
        uprightRoot.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(uprightRoot)

        let bbox = mesh.boundingBox
        if let geometry = mesh.makeGeometry() {
            let material = SCNMaterial()
            material.diffuse.contents = style.modelColor
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.55
            material.metalness.contents = 0.0
            geometry.materials = [material]

            let modelNode = SCNNode(geometry: geometry)
            if let bbox {
                let center = (bbox.min + bbox.max) * 0.5
                modelNode.position = SCNVector3(-center.x, -center.y, -center.z)
            }
            modelNode.castsShadow = true
            uprightRoot.addChildNode(modelNode)
        }

        // Half-extents in world space. The uprightRoot rotation (Rx(-90°)) maps
        // model (x, y, z) to world (x, z, -y), so the model's world Y range is
        // driven by its model-space Z (print height) and is centered on the
        // world origin because the mesh node is re-centered above.
        let halfExtent: SIMD3<Float> = bbox.map { ($0.max - $0.min) * 0.5 } ?? SIMD3<Float>(25, 25, 25)
        let groundY = -halfExtent.z

        if style.showGroundPlane {
            // A large flat plane acts as the ground/shadow catcher. (SCNFloor is
            // avoided on purpose: it sets up a reflection render pass — the
            // "FloorPass" — even with reflectivity 0, which errors every frame in
            // the Quick Look preview's live renderer and forces continuous
            // re-rendering, hanging previews of large meshes.)
            let extent = CGFloat(max(simd_length(halfExtent) * 40, 200))
            let plane = SCNPlane(width: extent, height: extent)
            let floorMaterial = SCNMaterial()
            floorMaterial.lightingModel = .physicallyBased
            floorMaterial.diffuse.contents = style.backgroundColor
            floorMaterial.roughness.contents = 1.0
            floorMaterial.metalness.contents = 0.0
            // Single-sided so the plane is back-face culled (invisible) when the
            // camera orbits below the model — otherwise this large plane fills
            // the view and greys out the model's underside.
            floorMaterial.isDoubleSided = false
            plane.materials = [floorMaterial]
            let floorNode = SCNNode(geometry: plane)
            // SCNPlane lies in its local XY plane (facing +Z); rotate it flat so
            // it faces up (+Y) at the model's base.
            floorNode.eulerAngles.x = -.pi / 2
            floorNode.position = SCNVector3(0, groundY, 0)
            floorNode.castsShadow = false
            scene.rootNode.addChildNode(floorNode)
        }

        let diagonal = max(simd_length(halfExtent) * 2, 1)
        let distance = diagonal * 2.0

        // Perspective, isometric-ish camera used as the default 3D view.
        let camera3D = SCNCamera()
        camera3D.usesOrthographicProjection = false
        camera3D.fieldOfView = 30
        camera3D.zNear = 0.01
        camera3D.zFar = Double(diagonal) * 10
        camera3D.automaticallyAdjustsZRange = true
        let camera3DNode = SCNNode()
        camera3DNode.name = "camera3D"
        camera3DNode.camera = camera3D
        camera3DNode.position = SCNVector3(distance, distance * 0.8, distance)
        camera3DNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera3DNode)

        // Orthographic front-elevation camera, looking along -Z toward the
        // origin. The uprightRoot rotation (Rx(-90°)) maps model (x, y, z) to
        // world (x, z, -y), so model width (X) reads as world X (image-right)
        // and model height (Z, print height) reads as world Y (image-up) —
        // i.e. this is a front view of the model as it sits on the print bed.
        let camera2D = SCNCamera()
        camera2D.usesOrthographicProjection = true
        camera2D.zNear = 0.01
        camera2D.zFar = Double(diagonal) * 10
        camera2D.automaticallyAdjustsZRange = true
        let frontHalfHeight = max(halfExtent.z, 1)
        let frontHalfWidth = max(halfExtent.x, 1)
        camera2D.orthographicScale = Double(max(frontHalfHeight, frontHalfWidth)) * 1.15
        let camera2DNode = SCNNode()
        camera2DNode.name = "camera2D"
        camera2DNode.camera = camera2D
        camera2DNode.position = SCNVector3(0, 0, distance)
        camera2DNode.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(camera2DNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 140
        ambientLight.color = NSColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        // Key light: upper-front-left, soft shadow-casting.
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.intensity = 850
        keyLight.color = NSColor.white
        keyLight.castsShadow = style.enableShadows
        if style.enableShadows {
            keyLight.shadowMode = .forward
            keyLight.shadowRadius = 6
            keyLight.shadowSampleCount = 16
            keyLight.shadowColor = NSColor(white: 0, alpha: 0.34)
            keyLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        }
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.position = SCNVector3(-distance * 0.7, distance * 0.85, distance * 0.5)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)

        // Fill light: lower, opposite side, no shadow — softens the key's contrast.
        let fillLight = SCNLight()
        fillLight.type = .directional
        fillLight.intensity = 280
        fillLight.color = NSColor.white
        fillLight.castsShadow = false
        let fillNode = SCNNode()
        fillNode.light = fillLight
        fillNode.position = SCNVector3(distance * 0.8, distance * 0.3, -distance * 0.8)
        fillNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(fillNode)

        // Subtle rim/back light for edge separation from the background.
        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.intensity = 120
        rimLight.color = NSColor.white
        rimLight.castsShadow = false
        let rimNode = SCNNode()
        rimNode.light = rimLight
        rimNode.position = SCNVector3(0, distance * 0.4, -distance)
        rimNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(rimNode)

        if style.enableEnvironmentLighting {
            scene.lightingEnvironment.contents = makeStudioEnvironmentContents()
            scene.lightingEnvironment.intensity = 0.6
        }

        return scene
    }

    /// A soft, neutral grayscale studio gradient used for image-based lighting
    /// so PBR materials pick up gentle, *untinted* reflections. A vertical
    /// gradient (bright top → mid-gray bottom) reads like a softbox overhead.
    private func makeStudioEnvironmentContents() -> Any {
        let width = 16, height = 128
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSColor(calibratedWhite: 0.7, alpha: 1.0)
        }
        let colors = [
            CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1),
            CGColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 1)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) else {
            return NSColor(calibratedWhite: 0.7, alpha: 1.0)
        }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0),
            options: []
        )
        guard let cgImage = ctx.makeImage() else {
            return NSColor(calibratedWhite: 0.7, alpha: 1.0)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}
#endif
