import simd

/// A flattened, indexed triangle mesh in plate/world space (already transformed
/// by any object/component/build-item transforms encountered while parsing).
public struct TriangleMesh {
    public var positions: [SIMD3<Float>]
    /// Three indices per triangle, zero-based into `positions`.
    public var indices: [UInt32]
    /// Per-triangle palette index (see `BuildPlate.palette`), when known.
    /// `nil` means "uncolored" (render with a single neutral material); when
    /// non-nil, its count always equals `triangleCount`.
    public var triangleColorIndices: [UInt8]?

    public init(positions: [SIMD3<Float>] = [], indices: [UInt32] = [], triangleColorIndices: [UInt8]? = nil) {
        self.positions = positions
        self.indices = indices
        self.triangleColorIndices = triangleColorIndices
    }

    public var triangleCount: Int { indices.count / 3 }

    public var isEmpty: Bool { positions.isEmpty || indices.isEmpty }

    public var boundingBox: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard var minV = positions.first else { return nil }
        var maxV = minV
        for p in positions {
            minV = simd_min(minV, p)
            maxV = simd_max(maxV, p)
        }
        return (minV, maxV)
    }

    /// Appends another mesh's triangles, re-basing its indices.
    ///
    /// `triangleColorIndices` are concatenated when both sides have them; if
    /// only one side has indices, the other side's triangles are padded with
    /// palette index `0` so the merged array's count still matches
    /// `triangleCount`; if neither side has indices, the merged mesh stays
    /// uncolored (`nil`).
    mutating func append(_ other: TriangleMesh) {
        // `UInt32(positions.count)` would trap past 4 billion vertices, but
        // `maxTriangles`/`maxTotalUncompressedBytes` budgets in practice keep
        // meshes far below that (a 4G-vertex mesh alone is >48 GiB of
        // positions), so this is intentionally left unguarded.
        let base = UInt32(positions.count)
        let selfTriangleCount = triangleCount
        let otherTriangleCount = other.triangleCount

        positions.append(contentsOf: other.positions)
        indices.append(contentsOf: other.indices.map { $0 + base })

        switch (triangleColorIndices, other.triangleColorIndices) {
        case (nil, nil):
            break
        case (var lhs?, nil):
            lhs.append(contentsOf: [UInt8](repeating: 0, count: otherTriangleCount))
            triangleColorIndices = lhs
        case (nil, let rhs?):
            var combined = [UInt8](repeating: 0, count: selfTriangleCount)
            combined.append(contentsOf: rhs)
            triangleColorIndices = combined
        case (var lhs?, let rhs?):
            lhs.append(contentsOf: rhs)
            triangleColorIndices = lhs
        }
    }

    /// Returns a mesh guaranteed safe to hand to a renderer: every index is
    /// `< positions.count`. Malformed/adversarial input (or a bug upstream)
    /// could otherwise produce an out-of-range index, which `SCNGeometryElement`
    /// would happily accept and which SceneKit/Metal could then read out of
    /// bounds on. The common case (already valid) is a cheap scan with no
    /// allocation; only meshes with a bad index pay for the filtering pass.
    func sanitizedForRendering() -> TriangleMesh {
        let vertexCount = positions.count
        guard indices.contains(where: { $0 >= vertexCount }) else { return self }

        var keptIndices: [UInt32] = []
        keptIndices.reserveCapacity(indices.count)
        var keptColors: [UInt8]? = triangleColorIndices != nil ? [] : nil
        let hasColors = triangleColorIndices?.count == triangleCount

        var triangle = 0
        var i = 0
        while i + 2 < indices.count {
            let i0 = indices[i], i1 = indices[i + 1], i2 = indices[i + 2]
            if i0 < vertexCount, i1 < vertexCount, i2 < vertexCount {
                keptIndices.append(contentsOf: [i0, i1, i2])
                if hasColors { keptColors?.append(triangleColorIndices![triangle]) }
            }
            i += 3
            triangle += 1
        }
        return TriangleMesh(positions: positions, indices: keptIndices, triangleColorIndices: hasColors ? keptColors : nil)
    }
}
