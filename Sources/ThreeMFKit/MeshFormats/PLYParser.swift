import Foundation

/// Parses PLY (Polygon File Format / Stanford Triangle Format) files:
/// ascii, binary_little_endian, and binary_big_endian, 1.0.
public enum PLYParser {

    enum ScalarType {
        case int8, uint8, int16, uint16, int32, uint32, float32, float64

        /// Byte size for binary encodings.
        var byteSize: Int {
            switch self {
            case .int8, .uint8: return 1
            case .int16, .uint16: return 2
            case .int32, .uint32, .float32: return 4
            case .float64: return 8
            }
        }

        init?(plyName: String) {
            switch plyName {
            case "char", "int8": self = .int8
            case "uchar", "uint8": self = .uint8
            case "short", "int16": self = .int16
            case "ushort", "uint16": self = .uint16
            case "int", "int32": self = .int32
            case "uint", "uint32": self = .uint32
            case "float", "float32": self = .float32
            case "double", "float64": self = .float64
            default: return nil
            }
        }
    }

    enum PropertyKind {
        case scalar(ScalarType)
        case list(countType: ScalarType, indexType: ScalarType)
    }

    struct Property {
        let kind: PropertyKind
        let name: String
    }

    struct Element {
        let name: String
        let count: Int
        var properties: [Property] = []
    }

    private enum Format {
        case ascii
        case binaryLittleEndian
        case binaryBigEndian
    }

    /// A maximum sane element instance count, guarding against corrupt
    /// headers claiming absurd counts relative to available bytes.
    private static let maxElementCount = 50_000_000

    public static func parse(data: Data) throws -> TriangleMesh {
        // Locate the "end_header" marker at the byte level first, since the
        // body may be raw binary and not valid UTF-8 as a whole.
        guard let endHeaderRange = data.range(of: Data("end_header".utf8)) else {
            throw ThreeMFError.malformedMesh("PLY file is missing 'end_header'.")
        }
        // Body begins right after the newline that terminates the end_header line.
        guard let newlineIndex = data[endHeaderRange.upperBound...].firstIndex(of: 0x0A) else {
            throw ThreeMFError.malformedMesh("PLY file is missing newline after 'end_header'.")
        }
        let bodyStart = data.index(after: newlineIndex)
        let headerData = data[data.startIndex..<endHeaderRange.upperBound]
        guard let headerText = String(data: headerData, encoding: .utf8) ?? String(data: headerData, encoding: .ascii) else {
            throw ThreeMFError.malformedMesh("PLY header is not valid ASCII/UTF-8 text.")
        }

        var format: Format? = nil
        var elements: [Element] = []

        let lines = headerText.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for (lineIndex, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if lineIndex == 0 {
                guard line == "ply" else {
                    throw ThreeMFError.malformedMesh("PLY file must start with 'ply'.")
                }
                continue
            }
            guard !line.isEmpty else { continue }
            let tokens = line.split(separator: " ").map(String.init)
            guard let keyword = tokens.first else { continue }

            switch keyword {
            case "comment", "obj_info":
                continue
            case "format":
                guard tokens.count >= 2 else {
                    throw ThreeMFError.malformedMesh("PLY 'format' line is malformed.")
                }
                switch tokens[1] {
                case "ascii": format = .ascii
                case "binary_little_endian": format = .binaryLittleEndian
                case "binary_big_endian": format = .binaryBigEndian
                default:
                    throw ThreeMFError.malformedMesh("Unsupported PLY format '\(tokens[1])'.")
                }
            case "element":
                guard tokens.count >= 3, let count = Int(tokens[2]) else {
                    throw ThreeMFError.malformedMesh("PLY 'element' line is malformed.")
                }
                guard count >= 0, count <= maxElementCount else {
                    throw ThreeMFError.malformedMesh("PLY element '\(tokens[1])' has an implausible count \(count).")
                }
                elements.append(Element(name: tokens[1], count: count))
            case "property":
                guard !elements.isEmpty else {
                    throw ThreeMFError.malformedMesh("PLY 'property' line appears before any 'element'.")
                }
                guard tokens.count >= 2 else {
                    throw ThreeMFError.malformedMesh("PLY 'property' line is malformed.")
                }
                if tokens[1] == "list" {
                    guard tokens.count >= 5,
                          let countType = ScalarType(plyName: tokens[2]),
                          let indexType = ScalarType(plyName: tokens[3]) else {
                        throw ThreeMFError.malformedMesh("PLY 'property list' line has unknown types: \(line)")
                    }
                    let name = tokens[4]
                    elements[elements.count - 1].properties.append(Property(kind: .list(countType: countType, indexType: indexType), name: name))
                } else {
                    guard let scalarType = ScalarType(plyName: tokens[1]), tokens.count >= 3 else {
                        throw ThreeMFError.malformedMesh("PLY 'property' line has unknown type: \(line)")
                    }
                    let name = tokens[2]
                    elements[elements.count - 1].properties.append(Property(kind: .scalar(scalarType), name: name))
                }
            default:
                continue
            }
        }

        guard let resolvedFormat = format else {
            throw ThreeMFError.malformedMesh("PLY file is missing a 'format' line.")
        }
        guard !elements.isEmpty else {
            throw ThreeMFError.malformedMesh("PLY file declares no elements.")
        }

        switch resolvedFormat {
        case .ascii:
            let bodyData = data[bodyStart...]
            guard let bodyText = String(data: bodyData, encoding: .utf8) ?? String(data: bodyData, encoding: .ascii) else {
                throw ThreeMFError.malformedMesh("PLY ascii body is not valid UTF-8/ASCII text.")
            }
            let tokens = bodyText.split(whereSeparator: { $0.isWhitespace })
            var cursor = ASCIICursor(tokens: tokens)
            return try extractMesh(elements: elements, cursor: &cursor)
        case .binaryLittleEndian, .binaryBigEndian:
            var cursor = BinaryCursor(data: data, offset: bodyStart, bigEndian: resolvedFormat == .binaryBigEndian)
            return try extractMesh(elements: elements, cursor: &cursor)
        }
    }

    // MARK: - Value cursors

    /// Abstracts sequential scalar reads over either ascii tokens or raw
    /// endianness-aware binary bytes, so element/property traversal logic
    /// can be shared between formats.
    private protocol ValueCursor {
        mutating func readScalar(_ type: ScalarType) throws -> Double
    }

    private struct ASCIICursor: ValueCursor {
        let tokens: [Substring]
        var index: Int = 0

        mutating func readScalar(_ type: ScalarType) throws -> Double {
            guard index < tokens.count else {
                throw ThreeMFError.malformedMesh("PLY ascii body ended unexpectedly.")
            }
            guard let value = Double(tokens[index]) else {
                throw ThreeMFError.malformedMesh("PLY ascii value is not numeric: \(tokens[index])")
            }
            index += 1
            return value
        }
    }

    private struct BinaryCursor: ValueCursor {
        let data: Data
        var offset: Int
        let bigEndian: Bool

        private mutating func readRawBytes(_ n: Int) throws -> [UInt8] {
            guard offset >= data.startIndex, offset + n <= data.endIndex else {
                throw ThreeMFError.malformedMesh("PLY binary body ended unexpectedly (need \(n) bytes at offset \(offset)).")
            }
            let bytes = Array(data[offset..<(offset + n)])
            offset += n
            return bytes
        }

        private mutating func readUInt(size: Int) throws -> UInt64 {
            let bytes = try readRawBytes(size)
            var value: UInt64 = 0
            if bigEndian {
                for byte in bytes { value = (value << 8) | UInt64(byte) }
            } else {
                for byte in bytes.reversed() { value = (value << 8) | UInt64(byte) }
            }
            return value
        }

        mutating func readScalar(_ type: ScalarType) throws -> Double {
            switch type {
            case .int8:
                let raw = try readUInt(size: 1)
                return Double(Int8(bitPattern: UInt8(truncatingIfNeeded: raw)))
            case .uint8:
                return Double(try readUInt(size: 1))
            case .int16:
                let raw = try readUInt(size: 2)
                return Double(Int16(bitPattern: UInt16(truncatingIfNeeded: raw)))
            case .uint16:
                return Double(try readUInt(size: 2))
            case .int32:
                let raw = try readUInt(size: 4)
                return Double(Int32(bitPattern: UInt32(truncatingIfNeeded: raw)))
            case .uint32:
                return Double(try readUInt(size: 4))
            case .float32:
                let raw = try readUInt(size: 4)
                return Double(Float(bitPattern: UInt32(truncatingIfNeeded: raw)))
            case .float64:
                let raw = try readUInt(size: 8)
                return Double(bitPattern: raw)
            }
        }
    }

    // MARK: - Element traversal

    /// Walks every declared element instance in file order, capturing vertex
    /// positions (`x`/`y`/`z` scalar properties) and face vertex-index lists
    /// (`vertex_indices`/`vertex_index`), while correctly consuming (and
    /// discarding) all other properties/elements so the cursor stays aligned.
    private static func extractMesh<C: ValueCursor>(elements: [Element], cursor: inout C) throws -> TriangleMesh {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        for element in elements {
            let isVertex = element.name == "vertex"
            let isFace = element.name == "face"

            var xIdx = -1, yIdx = -1, zIdx = -1
            if isVertex {
                for (i, property) in element.properties.enumerated() {
                    if case .scalar = property.kind {
                        switch property.name {
                        case "x": xIdx = i
                        case "y": yIdx = i
                        case "z": zIdx = i
                        default: break
                        }
                    }
                }
                guard xIdx >= 0, yIdx >= 0, zIdx >= 0 else {
                    throw ThreeMFError.malformedMesh("PLY 'vertex' element is missing x/y/z properties.")
                }
            }

            var faceListIdx = -1
            if isFace {
                for (i, property) in element.properties.enumerated() {
                    if case .list = property.kind, property.name == "vertex_indices" || property.name == "vertex_index" {
                        faceListIdx = i
                        break
                    }
                }
                guard faceListIdx >= 0 else {
                    throw ThreeMFError.malformedMesh("PLY 'face' element is missing a vertex_indices list property.")
                }
            }

            for _ in 0..<element.count {
                var xv = 0.0, yv = 0.0, zv = 0.0
                var faceIndices: [UInt32] = []

                for (pi, property) in element.properties.enumerated() {
                    switch property.kind {
                    case .scalar(let type):
                        let value = try cursor.readScalar(type)
                        if isVertex {
                            if pi == xIdx { xv = value }
                            else if pi == yIdx { yv = value }
                            else if pi == zIdx { zv = value }
                        }
                    case .list(let countType, let indexType):
                        let countValue = try cursor.readScalar(countType)
                        guard countValue.isFinite, countValue >= 0, countValue <= 1_000_000 else {
                            throw ThreeMFError.malformedMesh("PLY list property has an implausible count \(countValue).")
                        }
                        let n = Int(countValue)
                        for _ in 0..<n {
                            let indexValue = try cursor.readScalar(indexType)
                            if isFace && pi == faceListIdx {
                                guard indexValue >= 0 else {
                                    throw ThreeMFError.malformedMesh("PLY face vertex index is negative.")
                                }
                                faceIndices.append(UInt32(indexValue))
                            }
                        }
                    }
                }

                if isVertex {
                    positions.append(SIMD3<Float>(Float(xv), Float(yv), Float(zv)))
                }
                if isFace {
                    guard faceIndices.count >= 3 else {
                        throw ThreeMFError.malformedMesh("PLY 'face' element has fewer than 3 vertex indices.")
                    }
                    // Triangulate an n-gon via a fan: (v0, vi, vi+1).
                    for i in 1..<(faceIndices.count - 1) {
                        indices.append(faceIndices[0])
                        indices.append(faceIndices[i])
                        indices.append(faceIndices[i + 1])
                    }
                }
            }
        }

        // Guard against face indices referencing vertices beyond the parsed
        // vertex element (a malformed file should never crash a consumer).
        if let maxIndex = indices.max(), Int(maxIndex) >= positions.count {
            throw ThreeMFError.malformedMesh("PLY face references vertex index \(maxIndex) but only \(positions.count) vertices were parsed.")
        }

        return TriangleMesh(positions: positions, indices: indices)
    }
}
