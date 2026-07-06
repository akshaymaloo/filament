#if canImport(SceneKit)
import SceneKit
import simd
#if canImport(AppKit)
import AppKit
#endif

public extension SCNScene {
    /// Returns the interactive perspective camera node (`"camera3D"`) added by
    /// `BuildPlate.makeScene(style:)`, if present.
    var previewCameraNode: SCNNode? {
        rootNode.childNode(withName: "camera3D", recursively: true)
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

    /// Groups this mesh's triangles by `triangleColorIndices`, building one
    /// `SCNGeometry` per distinct palette index, so each can be given its own
    /// per-filament material. Every geometry shares the same (smooth,
    /// per-vertex) position/normal sources as `makeGeometry()`, but its
    /// element only lists the triangles belonging to that color group.
    /// Returns an empty array if there is no (complete) per-triangle color
    /// data, or the mesh is empty.
    func makeColorGroupedGeometries() -> [(paletteIndex: UInt8, geometry: SCNGeometry)] {
        guard !isEmpty, let colorIndices = triangleColorIndices, colorIndices.count == triangleCount else { return [] }

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

        // Group triangles by palette index, preserving original triangle order within each group.
        var groupedIndices: [UInt8: [UInt32]] = [:]
        for triangle in 0..<triangleCount {
            let paletteIndex = colorIndices[triangle]
            let base = triangle * 3
            groupedIndices[paletteIndex, default: []].append(contentsOf: [indices[base], indices[base + 1], indices[base + 2]])
        }

        return groupedIndices.sorted { $0.key < $1.key }.compactMap { paletteIndex, triangleIndices -> (paletteIndex: UInt8, geometry: SCNGeometry)? in
            guard !triangleIndices.isEmpty else { return nil }
            let indexData = triangleIndices.withUnsafeBufferPointer { Data(buffer: $0) }
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: triangleIndices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )
            let geometry = SCNGeometry(sources: [positionSource, normalSource], elements: [element])
            return (paletteIndex, geometry)
        }
    }
}

/// Parses a `"#RRGGBB"`/`"#RRGGBBAA"` filament color hex string into an
/// `NSColor`; falls back to `fallback` on any malformed input.
private func parseFilamentColor(_ hex: String, fallback: NSColor) -> NSColor {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return fallback }
    let hasAlpha = s.count == 8
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
    if hasAlpha {
        r = CGFloat((value >> 24) & 0xFF) / 255.0
        g = CGFloat((value >> 16) & 0xFF) / 255.0
        b = CGFloat((value >> 8) & 0xFF) / 255.0
        a = CGFloat(value & 0xFF) / 255.0
    } else {
        r = CGFloat((value >> 16) & 0xFF) / 255.0
        g = CGFloat((value >> 8) & 0xFF) / 255.0
        b = CGFloat(value & 0xFF) / 255.0
        a = 1.0
    }
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

public extension BuildPlate {
    /// Builds a scene containing this plate's mesh (upright, Z-up rotated into
    /// SceneKit's Y-up space), a perspective camera ("camera3D") framed to fill
    /// the viewport, and soft studio lighting with an optional ground-contact
    /// shadow and image-based environment reflections.
    /// Construction only — no offscreen rendering is performed.
    func makeScene(style: PreviewStyle = .default) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = style.backgroundColor

        // 3D-printing content is authored Z-up; SceneKit is Y-up.
        let uprightRoot = SCNNode()
        uprightRoot.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(uprightRoot)

        let bbox = mesh.boundingBox
        let colorGroups: [(paletteIndex: UInt8, geometry: SCNGeometry)] =
            (style.useModelColors && !palette.isEmpty) ? mesh.makeColorGroupedGeometries() : []

        if !colorGroups.isEmpty {
            // Multi-color path: one SCNGeometry/material per distinct
            // filament, grouped under a single node so the model still
            // centers/rotates as one unit.
            let modelNode = SCNNode()
            for (paletteIndex, geometry) in colorGroups {
                let material = SCNMaterial()
                let hex = Int(paletteIndex) < palette.count ? palette[Int(paletteIndex)] : nil
                material.diffuse.contents = hex.map { parseFilamentColor($0, fallback: style.modelColor) } ?? style.modelColor
                material.lightingModel = .physicallyBased
                material.roughness.contents = 0.55
                material.metalness.contents = 0.0
                geometry.materials = [material]

                let colorNode = SCNNode(geometry: geometry)
                colorNode.castsShadow = true
                modelNode.addChildNode(colorNode)
            }
            if let bbox {
                let center = (bbox.min + bbox.max) * 0.5
                modelNode.position = SCNVector3(-center.x, -center.y, -center.z)
            }
            modelNode.castsShadow = true
            uprightRoot.addChildNode(modelNode)
        } else if let geometry = mesh.makeGeometry() {
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

        // Frame so the model fills ~80% of the viewport on open, noticeably
        // larger than a bounding-sphere fit. Height and footprint are handled
        // separately: the vertical extent reads ~1:1 in the iso view, while the
        // footprint's diagonal (its widest spread across a turntable spin)
        // foreshortens at the iso angle. We take the farther of the two
        // distances so whichever dimension dominates fills the frame without
        // clipping. The height target is below the footprint target because a
        // tall, frame-filling model is inflated by perspective foreshortening.
        let diagonal = max(simd_length(halfExtent) * 2, 1)
        let fullExtent = bbox.map { $0.max - $0.min } ?? SIMD3<Float>(50, 50, 50)
        let footprint = (fullExtent.x * fullExtent.x + fullExtent.y * fullExtent.y).squareRoot()
        let cameraFOV: CGFloat = 30
        let halfFOV = Float(cameraFOV / 2) * .pi / 180
        let tanHalfFOV = tan(halfFOV)
        // Distance so the model height spans ~0.80 of the vertical field of view
        // (perspective inflates this to fill for tall, solid prints).
        let heightDistance = (max(fullExtent.z, 1) / (2 * 0.80)) / tanHalfFOV
        // Distance so the footprint diagonal spans ~0.92 of the field of view;
        // it foreshortens to ~80% at the iso angle and stays framed while
        // orbiting (its projected width never exceeds this fraction).
        let footprintDistance = (max(footprint, 1) / (2 * 0.92)) / tanHalfFOV
        let effectiveDistance = max(heightDistance, footprintDistance)
        // `distance` is the per-axis component of the (1, 0.8, 1) camera
        // position, reused below for light placement.
        let isoMagnitude = simd_length(SIMD3<Float>(1, 0.8, 1))
        let distance = effectiveDistance / isoMagnitude

        // Perspective, isometric-ish camera used as the default 3D view.
        let camera3D = SCNCamera()
        camera3D.usesOrthographicProjection = false
        camera3D.fieldOfView = cameraFOV
        camera3D.zNear = 0.01
        camera3D.zFar = Double(diagonal) * 10
        camera3D.automaticallyAdjustsZRange = true
        let camera3DNode = SCNNode()
        camera3DNode.name = "camera3D"
        camera3DNode.camera = camera3D
        camera3DNode.position = SCNVector3(distance, distance * 0.8, distance)
        camera3DNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera3DNode)

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
