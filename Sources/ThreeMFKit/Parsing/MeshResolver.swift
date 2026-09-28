import Foundation
import simd

/// Resolves the 3MF object/component graph into world-space meshes.
///
/// The 3MF Production Extension allows `<component>` elements to reference
/// objects defined in a completely separate model part (a different zip
/// entry), via the `p:path` attribute. Resolution therefore has to track
/// *which part* an object id is being looked up in, not just the id itself.
enum MeshResolver {
    /// Supplies the object table for a given model part. `partPath == nil`
    /// means the root model part; otherwise it is a normalized (no leading
    /// `/`) zip entry path to an external model part.
    typealias PartProvider = (_ partPath: String?) throws -> [Int: ObjectDefinition]

    /// Hard ceilings applied even when the caller sets no `maxTriangles`, so
    /// a tiny malicious package can't expand into an out-of-memory crash.
    static let absoluteTriangleCeiling = 50_000_000
    static let maxComponentVisits = 1_000_000

    /// Per-load resolution state shared across every build item.
    struct ResolutionContext {
        var visiting = Set<String>()
        var visitedNodes = 0
        var resolvedTriangles = 0
        let triangleLimit: Int
        let shouldCancel: (() -> Bool)?

        init(triangleLimit: Int, shouldCancel: (() -> Bool)?) {
            self.triangleLimit = triangleLimit
            self.shouldCancel = shouldCancel
        }
    }

    /// Strips a single leading `/` from a Production Extension `p:path`
    /// value, turning the package-root-absolute path into a plain zip entry
    /// path (e.g. `/3D/Objects/object_25.model` -> `3D/Objects/object_25.model`).
    static func normalizePartPath(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }

    /// Resolves the mesh for a single object within `partPath`, recursively
    /// composing component transforms and following cross-part component
    /// references. `accumulated` is the transform to apply to this object's
    /// own vertex data (already including everything above it, e.g. the
    /// build item transform).
    static func resolveMesh(
        provider: PartProvider,
        partPath: String?,
        objectId: Int,
        accumulated: Matrix4,
        objectExtruder: [Int: Int],
        context: inout ResolutionContext
    ) throws -> TriangleMesh {
        // A small file can describe an exponentially large mesh through a
        // component DAG (A = 10x B, B = 10x C, ...); the cycle guard alone
        // doesn't stop that, so bound both the node visits and the triangles
        // produced, and poll cancellation as we go.
        context.visitedNodes += 1
        guard context.visitedNodes <= Self.maxComponentVisits else {
            throw ThreeMFError.malformedXML("component graph expands to more than \(Self.maxComponentVisits) object references")
        }
        if context.visitedNodes & 0xFFF == 0, let shouldCancel = context.shouldCancel, shouldCancel() {
            throw ThreeMFError.cancelled
        }

        // The cycle-guard key must include the part, since the same object id
        // can legitimately exist independently in different parts.
        let key = "\(partPath ?? "")#\(objectId)"
        guard !context.visiting.contains(key) else {
            throw ThreeMFError.malformedXML("cyclic component reference involving object \(objectId) in part \(partPath ?? "<root>")")
        }

        let objects = try provider(partPath)
        guard let definition = objects[objectId] else {
            // Referenced object is missing; degrade gracefully to an empty mesh.
            return TriangleMesh()
        }
        context.visiting.insert(key)
        defer { context.visiting.remove(key) }

        switch definition {
        case .excluded:
            // "support"/"other" objects are excluded from the rendered mesh,
            // triangle count, and dimensions (but empty is still a valid
            // mesh, so e.g. Bambu plate assignment referencing this object
            // id doesn't break).
            return TriangleMesh()
        case .mesh(let mesh, let paintStates):
            guard !mesh.isEmpty else { return TriangleMesh() }
            context.resolvedTriangles += mesh.triangleCount
            guard context.resolvedTriangles <= context.triangleLimit else {
                throw ThreeMFError.meshTooLarge(triangles: context.resolvedTriangles, limit: context.triangleLimit)
            }
            let transformed = mesh.positions.map { accumulated.apply(to: $0) }
            // Per-triangle palette index: a painted triangle (paintState >= 1)
            // uses its own decoded extruder; otherwise it falls back to this
            // object's base extruder (default 1, i.e. palette index 0).
            let baseExtruder = objectExtruder[objectId] ?? 1
            let colorIndices: [UInt8] = (0..<mesh.triangleCount).map { i in
                let paintState = i < paintStates.count ? paintStates[i] : 0
                let extruder = paintState >= 1 ? paintState : baseExtruder
                return UInt8(max(0, min(extruder - 1, 254)))
            }
            return TriangleMesh(positions: transformed, indices: mesh.indices, triangleColorIndices: colorIndices)
        case .components(let components):
            var combined = TriangleMesh()
            for component in components {
                // An explicit p:path switches lookup to that external part;
                // otherwise the component stays within the current part.
                let childPath = component.path.map(Self.normalizePartPath) ?? partPath
                let childTransform = component.transform.compose(accumulated)
                let childMesh = try resolveMesh(
                    provider: provider,
                    partPath: childPath,
                    objectId: component.objectId,
                    accumulated: childTransform,
                    objectExtruder: objectExtruder,
                    context: &context
                )
                combined.append(childMesh)
            }
            return combined
        }
    }

    /// Resolves every top-level build item, returning `(rootObjectId, mesh)` pairs
    /// in build-item order. `rootObjectId` is the item's own `objectid`, which is
    /// what Bambu plate metadata (`model_instance/@object_id`) refers to. Build
    /// items always start resolution in the root model part. `objectExtruder`
    /// maps object id -> 1-based base extruder, from `model_settings.config`
    /// (default 1 when an object is absent from the map).
    static func resolveBuildItems(
        buildItems: [BuildItem],
        provider: PartProvider,
        objectExtruder: [Int: Int] = [:],
        maxTriangles: Int? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> [(objectId: Int, mesh: TriangleMesh)] {
        var results: [(objectId: Int, mesh: TriangleMesh)] = []
        var context = ResolutionContext(
            triangleLimit: maxTriangles ?? Self.absoluteTriangleCeiling,
            shouldCancel: shouldCancel
        )
        for item in buildItems {
            if let shouldCancel, shouldCancel() {
                throw ThreeMFError.cancelled
            }
            context.visiting.removeAll(keepingCapacity: true)
            let mesh = try resolveMesh(
                provider: provider,
                partPath: nil,
                objectId: item.objectId,
                accumulated: item.transform,
                objectExtruder: objectExtruder,
                context: &context
            )
            results.append((objectId: item.objectId, mesh: mesh))
        }
        return results
    }
}
