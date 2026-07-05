import simd

/// A flattened, indexed triangle mesh in plate/world space (already transformed
/// by any object/component/build-item transforms encountered while parsing).
public struct TriangleMesh {
    public var positions: [SIMD3<Float>]
    /// Three indices per triangle, zero-based into `positions`.
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>] = [], indices: [UInt32] = []) {
        self.positions = positions
        self.indices = indices
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
    mutating func append(_ other: TriangleMesh) {
        let base = UInt32(positions.count)
        positions.append(contentsOf: other.positions)
        indices.append(contentsOf: other.indices.map { $0 + base })
    }
}
