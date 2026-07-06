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
        visiting: inout Set<String>
    ) throws -> TriangleMesh {
        // The cycle-guard key must include the part, since the same object id
        // can legitimately exist independently in different parts.
        let key = "\(partPath ?? "")#\(objectId)"
        guard !visiting.contains(key) else {
            throw ThreeMFError.malformedXML("cyclic component reference involving object \(objectId) in part \(partPath ?? "<root>")")
        }

        let objects = try provider(partPath)
        guard let definition = objects[objectId] else {
            // Referenced object is missing; degrade gracefully to an empty mesh.
            return TriangleMesh()
        }
        visiting.insert(key)
        defer { visiting.remove(key) }

        switch definition {
        case .mesh(let mesh, let paintStates):
            guard !mesh.isEmpty else { return TriangleMesh() }
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
                    visiting: &visiting
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
        objectExtruder: [Int: Int] = [:]
    ) throws -> [(objectId: Int, mesh: TriangleMesh)] {
        var results: [(objectId: Int, mesh: TriangleMesh)] = []
        for item in buildItems {
            var visiting = Set<String>()
            let mesh = try resolveMesh(
                provider: provider,
                partPath: nil,
                objectId: item.objectId,
                accumulated: item.transform,
                objectExtruder: objectExtruder,
                visiting: &visiting
            )
            results.append((objectId: item.objectId, mesh: mesh))
        }
        return results
    }
}
