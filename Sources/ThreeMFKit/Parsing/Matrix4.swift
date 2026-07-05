import simd

/// A 3MF affine transform: 3x3 linear part `m` (rows are basis vectors) plus a
/// translation `t`. Parsed from the 12 space-separated floats in a `transform`
/// attribute, row-major with an implicit fixed last column `(0, 0, 0, 1)`:
///
///   m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32
///
/// Applying to a vertex v = (vx, vy, vz):
///   x' = m00*vx + m10*vy + m20*vz + m30
///   y' = m01*vx + m11*vy + m21*vz + m31
///   z' = m02*vx + m12*vy + m22*vz + m32
struct Matrix4 {
    // Row-major 3x3 (rows = basis vectors) stored as three rows.
    var row0: SIMD3<Float>
    var row1: SIMD3<Float>
    var row2: SIMD3<Float>
    var translation: SIMD3<Float>

    static let identity = Matrix4(
        row0: SIMD3(1, 0, 0), row1: SIMD3(0, 1, 0), row2: SIMD3(0, 0, 1),
        translation: SIMD3(0, 0, 0)
    )

    /// Parses a 3MF `transform` attribute string (12 space-separated floats).
    /// Returns `.identity` for a missing/empty string.
    static func parse(_ string: String?) -> Matrix4 {
        guard let string, !string.trimmingCharacters(in: .whitespaces).isEmpty else {
            return .identity
        }
        let parts = string.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard parts.count == 12 else { return .identity }
        let values = parts.compactMap { Float($0) }
        guard values.count == 12 else { return .identity }
        return Matrix4(
            row0: SIMD3(values[0], values[1], values[2]),
            row1: SIMD3(values[3], values[4], values[5]),
            row2: SIMD3(values[6], values[7], values[8]),
            translation: SIMD3(values[9], values[10], values[11])
        )
    }

    /// Applies this transform to a point.
    func apply(to v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            row0.x * v.x + row1.x * v.y + row2.x * v.z + translation.x,
            row0.y * v.x + row1.y * v.y + row2.y * v.z + translation.y,
            row0.z * v.x + row1.z * v.y + row2.z * v.z + translation.z
        )
    }

    /// Composes `self` followed by `outer`, i.e. `outer.apply(self.apply(v)) == self.compose(outer).apply(v)`.
    func compose(_ outer: Matrix4) -> Matrix4 {
        func transformDirection(_ v: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(
                outer.row0.x * v.x + outer.row1.x * v.y + outer.row2.x * v.z,
                outer.row0.y * v.x + outer.row1.y * v.y + outer.row2.y * v.z,
                outer.row0.z * v.x + outer.row1.z * v.y + outer.row2.z * v.z
            )
        }
        return Matrix4(
            row0: transformDirection(row0),
            row1: transformDirection(row1),
            row2: transformDirection(row2),
            translation: outer.apply(to: translation)
        )
    }
}
