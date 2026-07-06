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
}
