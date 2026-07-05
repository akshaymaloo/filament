import Foundation

/// Parses STL (STereoLithography) files, both binary and ASCII variants.
public enum STLParser {
    private static let binaryHeaderSize = 80
    private static let binaryRecordSize = 50 // 12 (normal) + 36 (3 verts) + 2 (attr byte count)

    public static func parse(data: Data) throws -> TriangleMesh {
        if let binaryCount = plausibleBinaryTriangleCount(data: data) {
            return try parseBinary(data: data, triangleCount: binaryCount)
        }
        if isASCII(data: data) {
            return try parseASCII(data: data)
        }
        throw ThreeMFError.malformedMesh("Unable to determine STL variant (binary/ascii) or file is corrupt.")
    }

    /// Returns a plausible binary triangle count if the file's total size
    /// exactly matches `84 + 50*count`, else nil. Some binary STL files begin
    /// with the ASCII "solid" prefix, so this byte-size check takes priority
    /// over prefix sniffing.
    private static func plausibleBinaryTriangleCount(data: Data) -> Int? {
        guard data.count >= binaryHeaderSize + 4 else { return nil }
        let reader = ByteReader(data)
        guard let count = try? reader.u32(binaryHeaderSize) else { return nil }
        let expected = binaryHeaderSize + 4 + Int(count) * binaryRecordSize
        guard expected == data.count else { return nil }
        return Int(count)
    }

    private static func isASCII(data: Data) -> Bool {
        // Look at a prefix, trimmed of leading whitespace, for a case-insensitive "solid" token.
        let prefixLength = min(data.count, 512)
        guard let prefix = String(data: data.prefix(prefixLength), encoding: .utf8) else { return false }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("solid")
    }

    private static func parseBinary(data: Data, triangleCount: Int) throws -> TriangleMesh {
        guard triangleCount >= 0 else {
            throw ThreeMFError.malformedMesh("STL binary triangle count is negative.")
        }
        let requiredBytes = binaryHeaderSize + 4 + triangleCount * binaryRecordSize
        guard requiredBytes <= data.count else {
            throw ThreeMFError.malformedMesh("STL binary file is smaller than declared triangle count requires.")
        }

        let reader = ByteReader(data)
        var builder = VertexDeduper()
        var indices: [UInt32] = []
        indices.reserveCapacity(triangleCount * 3)

        var offset = binaryHeaderSize + 4
        for _ in 0..<triangleCount {
            offset += 12 // skip normal
            var triIndices: [UInt32] = []
            triIndices.reserveCapacity(3)
            for _ in 0..<3 {
                let x = try reader.f32(offset); offset += 4
                let y = try reader.f32(offset); offset += 4
                let z = try reader.f32(offset); offset += 4
                triIndices.append(builder.index(for: SIMD3<Float>(x, y, z)))
            }
            offset += 2 // attribute byte count
            indices.append(contentsOf: triIndices)
        }

        return TriangleMesh(positions: builder.positions, indices: indices)
    }

    private static func parseASCII(data: Data) throws -> TriangleMesh {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ThreeMFError.malformedMesh("STL ASCII file is not valid UTF-8/ASCII text.")
        }

        var builder = VertexDeduper()
        var indices: [UInt32] = []
        var pendingTriangleIndices: [UInt32] = []
        pendingTriangleIndices.reserveCapacity(3)

        // Tokenize on any whitespace; tolerant of arbitrary formatting.
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        var i = 0
        while i < tokens.count {
            if tokens[i].caseInsensitiveCompare("vertex") == .orderedSame {
                guard i + 3 < tokens.count,
                      let x = Float(tokens[i + 1]),
                      let y = Float(tokens[i + 2]),
                      let z = Float(tokens[i + 3]) else {
                    throw ThreeMFError.malformedMesh("STL ASCII 'vertex' line missing numeric components.")
                }
                pendingTriangleIndices.append(builder.index(for: SIMD3<Float>(x, y, z)))
                if pendingTriangleIndices.count == 3 {
                    indices.append(contentsOf: pendingTriangleIndices)
                    pendingTriangleIndices.removeAll(keepingCapacity: true)
                }
                i += 4
            } else {
                i += 1
            }
        }

        guard pendingTriangleIndices.isEmpty else {
            throw ThreeMFError.malformedMesh("STL ASCII file has a facet with an incomplete vertex triplet.")
        }

        return TriangleMesh(positions: builder.positions, indices: indices)
    }
}

/// Deduplicates identical vertex positions (by exact float bit pattern) while
/// building up compact `positions`/`indices` arrays. Shared by STL/PLY
/// parsers, which both emit raw vertex streams without existing indices.
struct VertexDeduper {
    private var lookup: [UInt64Triple: UInt32] = [:]
    private(set) var positions: [SIMD3<Float>] = []

    mutating func index(for v: SIMD3<Float>) -> UInt32 {
        let key = UInt64Triple(x: v.x.bitPattern, y: v.y.bitPattern, z: v.z.bitPattern)
        if let existing = lookup[key] {
            return existing
        }
        let newIndex = UInt32(positions.count)
        positions.append(v)
        lookup[key] = newIndex
        return newIndex
    }

    struct UInt64Triple: Hashable {
        let x: UInt32
        let y: UInt32
        let z: UInt32
    }
}
