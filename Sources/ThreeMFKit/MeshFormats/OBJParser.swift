import Foundation

/// Parses Wavefront OBJ files (positions + face indices only; normals,
/// texture coordinates, materials, and groups are ignored).
public enum OBJParser {
    public static func parse(data: Data) throws -> TriangleMesh {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ThreeMFError.malformedMesh("OBJ file is not valid UTF-8/ASCII text.")
        }

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // Strip a trailing comment and surrounding whitespace.
            let withoutComment = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let line = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let keyword = tokens.first else { continue }

            switch keyword {
            case "v":
                guard tokens.count >= 4,
                      let x = Float(tokens[1]),
                      let y = Float(tokens[2]),
                      let z = Float(tokens[3]) else {
                    throw ThreeMFError.malformedMesh("OBJ 'v' line missing numeric components: \(line)")
                }
                positions.append(SIMD3<Float>(x, y, z))
            case "f":
                let faceTokens = tokens.dropFirst()
                guard faceTokens.count >= 3 else {
                    throw ThreeMFError.malformedMesh("OBJ 'f' line needs at least 3 vertices: \(line)")
                }
                var faceIndices: [UInt32] = []
                faceIndices.reserveCapacity(faceTokens.count)
                for token in faceTokens {
                    let resolved = try resolvePositionIndex(token: token, vertexCount: positions.count)
                    faceIndices.append(resolved)
                }
                // Triangulate an n-gon via a fan: (v0, vi, vi+1).
                for i in 1..<(faceIndices.count - 1) {
                    indices.append(faceIndices[0])
                    indices.append(faceIndices[i])
                    indices.append(faceIndices[i + 1])
                }
            default:
                // vt, vn, g, o, usemtl, mtllib, s, etc. are ignored.
                continue
            }
        }

        return TriangleMesh(positions: positions, indices: indices)
    }

    /// Parses a face vertex token of the form `v`, `v/vt`, `v//vn`, or
    /// `v/vt/vn`, returning only the (0-based, resolved) position index.
    /// Negative indices are relative to the current vertex count.
    private static func resolvePositionIndex(token: Substring, vertexCount: Int) throws -> UInt32 {
        let components = token.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = components.first, let raw = Int(first) else {
            throw ThreeMFError.malformedMesh("OBJ face token has no vertex index: \(token)")
        }
        let oneBasedIndex: Int
        if raw < 0 {
            oneBasedIndex = vertexCount + raw + 1
        } else {
            oneBasedIndex = raw
        }
        guard oneBasedIndex >= 1, oneBasedIndex <= vertexCount else {
            throw ThreeMFError.malformedMesh("OBJ face vertex index \(raw) out of range (vertex count \(vertexCount)).")
        }
        return UInt32(oneBasedIndex - 1)
    }
}
