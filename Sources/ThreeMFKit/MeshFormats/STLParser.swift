import Foundation

/// Parses STL (STereoLithography) files, both binary and ASCII variants.
public enum STLParser {
    private static let binaryHeaderSize = 80
    private static let binaryRecordSize = 50 // 12 (normal) + 36 (3 verts) + 2 (attr byte count)

    /// The result of sniffing which STL variant `data` is, and (for binary)
    /// the triangle count to actually use.
    private enum Variant {
        case binary(triangleCount: Int)
        case ascii
    }

    public static func parse(data: Data, maxTriangles: Int? = nil, shouldCancel: (() -> Bool)? = nil) throws -> TriangleMesh {
        switch try classify(data: data) {
        case .binary(let triangleCount):
            return try parseBinary(data: data, triangleCount: triangleCount, maxTriangles: maxTriangles, shouldCancel: shouldCancel)
        case .ascii:
            return try parseASCII(data: data, maxTriangles: maxTriangles, shouldCancel: shouldCancel)
        }
    }

    /// Whether `data` looks like some variant of STL at all, for content
    /// sniffing when the file extension is missing/unrecognized. Shares the
    /// exact same classification logic `parse(data:)` uses.
    static func looksLikeSTL(data: Data) -> Bool {
        (try? classify(data: data)) != nil
    }

    /// Classifies `data` as binary or ASCII STL. Binary files exported by
    /// real-world tools don't always match `84 + 50*count` exactly (trailing
    /// padding, a zero/garbage header count, etc.), and a binary file's
    /// 80-byte header can itself start with the ASCII "solid" prefix — so
    /// this checks multiple signals in order of decreasing confidence rather
    /// than a single exact-size test.
    private static func classify(data: Data) throws -> Variant {
        let declaredCount = declaredBinaryTriangleCount(data: data)

        // 1. Exact-size match (header + count field + count*record == size)
        // is the strongest possible signal, and takes priority over "solid"
        // prefix sniffing (some binary STL files begin with "solid").
        if let declaredCount, isExactBinarySize(data: data, triangleCount: declaredCount) {
            return .binary(triangleCount: declaredCount)
        }

        // 2. Genuine ASCII content: "solid" prefix plus facet/endsolid
        // keywords and no embedded NULs in the early bytes (a binary file's
        // header happening to start with "solid" won't also look like this).
        if looksLikeGenuineASCII(data: data) {
            return .ascii
        }

        // 3. A plausible declared count whose required bytes fit within the
        // file, ignoring any trailing bytes (padding/extra data).
        if let declaredCount, declaredCount > 0,
           binaryHeaderSize + 4 + declaredCount * binaryRecordSize <= data.count {
            return .binary(triangleCount: declaredCount)
        }

        // 4. The declared count is missing/implausible, but the body size
        // (after the fixed header) is a clean, positive multiple of the
        // per-triangle record size. (Step 2 already ruled out genuine ASCII
        // content, including a binary header that merely starts with
        // "solid" but has no facet/endsolid keywords.)
        if data.count > binaryHeaderSize + 4 {
            let bodySize = data.count - binaryHeaderSize - 4
            if bodySize > 0, bodySize % binaryRecordSize == 0 {
                return .binary(triangleCount: bodySize / binaryRecordSize)
            }
        }

        // 5. Fall back to ASCII for anything at least announcing itself as
        // "solid" (e.g. a valid-but-empty or oddly formatted ASCII file).
        if hasSolidPrefix(data: data) {
            return .ascii
        }

        throw ThreeMFError.malformedMesh("Unable to determine STL variant (binary/ascii) or file is corrupt.")
    }

    /// Reads the declared triangle count at byte offset 80 (the UInt32 LE
    /// field right after the 80-byte header), if the file is even that long.
    private static func declaredBinaryTriangleCount(data: Data) -> Int? {
        guard data.count >= binaryHeaderSize + 4 else { return nil }
        let reader = ByteReader(data)
        guard let count = try? reader.u32(binaryHeaderSize) else { return nil }
        return Int(count)
    }

    private static func isExactBinarySize(data: Data, triangleCount: Int) -> Bool {
        binaryHeaderSize + 4 + triangleCount * binaryRecordSize == data.count
    }

    private static func hasSolidPrefix(data: Data) -> Bool {
        // Look at a prefix, trimmed of leading whitespace, for a case-insensitive "solid" token.
        let prefixLength = min(data.count, 512)
        guard let prefix = String(data: data.prefix(prefixLength), encoding: .utf8) else { return false }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("solid")
    }

    /// A binary STL's 80-byte header can start with "solid" too, so the
    /// prefix alone isn't enough: also require an ASCII-STL keyword
    /// ("facet"/"endsolid") to appear in the first few KB, and that the same
    /// window contains no NUL bytes (binary records are full of them).
    private static func looksLikeGenuineASCII(data: Data) -> Bool {
        guard hasSolidPrefix(data: data) else { return false }
        let windowLength = min(data.count, 4096)
        let window = data.prefix(windowLength)
        guard !window.contains(0) else { return false }
        guard let text = String(data: window, encoding: .utf8) ?? String(data: window, encoding: .ascii) else { return false }
        let lower = text.lowercased()
        return lower.contains("facet") || lower.contains("endsolid")
    }

    private static func parseBinary(data: Data, triangleCount: Int, maxTriangles: Int?, shouldCancel: (() -> Bool)?) throws -> TriangleMesh {
        guard triangleCount >= 0 else {
            throw ThreeMFError.malformedMesh("STL binary triangle count is negative.")
        }
        if let maxTriangles, triangleCount > maxTriangles {
            throw ThreeMFError.meshTooLarge(triangles: triangleCount, limit: maxTriangles)
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
        for triangleIndex in 0..<triangleCount {
            if triangleIndex & 0xFFFF == 0, let shouldCancel, shouldCancel() {
                throw ThreeMFError.cancelled
            }
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

    private static func parseASCII(data: Data, maxTriangles: Int?, shouldCancel: (() -> Bool)?) throws -> TriangleMesh {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ThreeMFError.malformedMesh("STL ASCII file is not valid UTF-8/ASCII text.")
        }

        var builder = VertexDeduper()
        var indices: [UInt32] = []
        var pendingTriangleIndices: [UInt32] = []
        pendingTriangleIndices.reserveCapacity(3)
        var triangleCount = 0

        // Tokenize on any whitespace; tolerant of arbitrary formatting.
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        var i = 0
        while i < tokens.count {
            if i & 0xFFFF == 0, let shouldCancel, shouldCancel() {
                throw ThreeMFError.cancelled
            }
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
                    triangleCount += 1
                    if let maxTriangles, triangleCount > maxTriangles {
                        throw ThreeMFError.meshTooLarge(triangles: triangleCount, limit: maxTriangles)
                    }
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
