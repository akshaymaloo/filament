import Foundation
import simd

/// Parsed representation of a single `<object>` resource before build-time resolution.
enum ObjectDefinition {
    /// `paintStates` is parallel to the mesh's triangles: the decoded
    /// `paint_color` extruder index (1-based) for each triangle, or `0` when
    /// the triangle has no `paint_color` attribute (i.e. use the object's
    /// base extruder from `model_settings.config`).
    case mesh(TriangleMesh, paintStates: [Int])
    /// `path`, when non-nil, is the raw (un-normalized) Production Extension
    /// `p:path` value pointing at an external model part that owns the
    /// referenced object; `nil` means the component lives in the same part.
    case components([(objectId: Int, transform: Matrix4, path: String?)])
    /// The object's `type` attribute is `support` (auto-generated print
    /// supports) or `other` (not meant to be printed/rendered). Per the 3MF
    /// core spec these must be excluded from the rendered mesh, triangle
    /// count, and dimensions; `model`/`solidsupport`/`surface` are kept.
    case excluded
}

/// A parsed `<item>` from `<build>`.
struct BuildItem {
    let objectId: Int
    let transform: Matrix4
}

/// A hand-written streaming scanner for the 3MF core schema
/// (`3D/3dmodel.model`).
///
/// The 3MF model part is machine-generated, well-formed XML dominated by
/// millions of tiny `<vertex .../>` and `<triangle .../>` elements. Foundation's
/// `XMLParser` allocates a fresh `[String: String]` attribute dictionary (and a
/// `String` per attribute name/value) for *every* element, which makes large
/// meshes (millions of triangles) take many seconds to load. This scanner walks
/// the raw UTF-8 bytes once, extracting only the attributes each element needs
/// and parsing numbers directly from the buffer, which is roughly an order of
/// magnitude faster on big files.
final class ModelXMLParser {
    private(set) var unit: LengthUnit = .millimeter
    private(set) var objects: [Int: ObjectDefinition] = [:]
    private(set) var buildItems: [BuildItem] = []

    private let parseMesh: Bool
    /// Triangle budget across every object in this part (i.e. this one
    /// `.model` file); `nil` means unlimited. The loader additionally checks
    /// the total across every resolved build item (which can multiply a
    /// single part's triangles via repeated component references).
    private let maxTriangles: Int?
    private let shouldCancel: (() -> Bool)?
    private var totalTriangleCount = 0
    /// Counts elements processed so `shouldCancel` is polled cheaply (every
    /// 65536 elements) rather than on every tiny `<vertex>`/`<triangle>`.
    private var elementPollCounter = 0

    // Parsing state.
    private var currentObjectId: Int?
    private var currentObjectType: String?
    private var currentVertices: [SIMD3<Float>] = []
    private var currentIndices: [UInt32] = []
    private var currentPaintStates: [Int] = []
    private var currentComponents: [(objectId: Int, transform: Matrix4, path: String?)] = []
    private var inVertices = false
    private var inTriangles = false
    private var inComponents = false

    init(parseMesh: Bool, maxTriangles: Int? = nil, shouldCancel: (() -> Bool)? = nil) {
        self.parseMesh = parseMesh
        self.maxTriangles = maxTriangles
        self.shouldCancel = shouldCancel
    }

    static func parse(data: Data, parseMesh: Bool, maxTriangles: Int? = nil, shouldCancel: (() -> Bool)? = nil) throws -> ModelXMLParser {
        let delegate = ModelXMLParser(parseMesh: parseMesh, maxTriangles: maxTriangles, shouldCancel: shouldCancel)
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let rawBase = raw.baseAddress, raw.count > 0 else { return }
            let bytes = rawBase.assumingMemoryBound(to: UInt8.self)
            try delegate.scan(bytes: bytes, count: raw.count)
        }
        return delegate
    }

    // MARK: - Scanner

    private func scan(bytes: UnsafePointer<UInt8>, count n: Int) throws {
        let lt = UInt8(ascii: "<")
        let gt = UInt8(ascii: ">")
        let slash = UInt8(ascii: "/")
        let bang = UInt8(ascii: "!")
        let question = UInt8(ascii: "?")
        let dash = UInt8(ascii: "-")
        let eqSign = UInt8(ascii: "=")

        var i = 0
        while i < n {
            // Advance to the next '<'.
            while i < n && bytes[i] != lt { i += 1 }
            if i >= n { break }
            i += 1
            if i >= n { break }

            let c = bytes[i]
            if c == slash {
                // End tag: </name>
                i += 1
                let nameStart = i
                while i < n && !isNameEnd(bytes[i]) { i += 1 }
                handleEnd(bytes: bytes, start: nameStart, end: i)
                while i < n && bytes[i] != gt { i += 1 }
                i += 1
                continue
            }

            if c == bang {
                // Comment <!-- ... -->, CDATA, or DOCTYPE. Skip past it.
                if i + 2 < n && bytes[i + 1] == dash && bytes[i + 2] == dash {
                    i += 3
                    while i + 2 < n && !(bytes[i] == dash && bytes[i + 1] == dash && bytes[i + 2] == gt) { i += 1 }
                    i += 3
                } else {
                    while i < n && bytes[i] != gt { i += 1 }
                    i += 1
                }
                continue
            }

            if c == question {
                // Processing instruction / XML declaration <? ... ?>.
                while i < n && bytes[i] != gt { i += 1 }
                i += 1
                continue
            }

            // Start (or self-closing) tag.
            let nameStart = i
            while i < n && !isNameEnd(bytes[i]) { i += 1 }
            let nameEnd = i
            let kind = elementKind(bytes: bytes, start: nameStart, end: nameEnd)

            // Poll cancellation cheaply: checking on every tiny <vertex>/
            // <triangle> element would itself become a measurable cost on
            // multi-million-triangle meshes.
            elementPollCounter += 1
            if elementPollCounter & 0xFFFF == 0, let shouldCancel, shouldCancel() {
                throw ThreeMFError.cancelled
            }

            handleStart(kind)

            // Consume attributes, detecting a self-closing "/>".
            var selfClosing = false
            while i < n {
                let b = bytes[i]
                if b == gt { i += 1; break }
                if b == slash { selfClosing = true; i += 1; continue }
                if isSpace(b) { i += 1; continue }

                // attribute name
                let anStart = i
                while i < n {
                    let ab = bytes[i]
                    if ab == eqSign || isSpace(ab) || ab == gt || ab == slash { break }
                    i += 1
                }
                let anEnd = i
                while i < n && isSpace(bytes[i]) { i += 1 }
                guard i < n && bytes[i] == eqSign else { continue }
                i += 1
                while i < n && isSpace(bytes[i]) { i += 1 }
                guard i < n else { break }
                let quote = bytes[i]
                guard quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") else { continue }
                i += 1
                let avStart = i
                while i < n && bytes[i] != quote { i += 1 }
                let avEnd = i
                if i < n { i += 1 } // past the closing quote

                handleAttribute(kind, bytes: bytes,
                                nameStart: anStart, nameEnd: anEnd,
                                valueStart: avStart, valueEnd: avEnd)
            }

            try finishStart(kind)
            if selfClosing {
                handleEnd(bytes: bytes, start: nameStart, end: nameEnd)
            }
        }
    }

    // MARK: - Element dispatch

    private enum ElementKind {
        case model, object, vertices, vertex, triangles, triangle
        case components, component, item, other
    }

    // Per-element attribute accumulators, reset in `handleStart`.
    private var attrObjectId: Int?
    private var attrType: String?
    private var attrX: Float = 0, attrY: Float = 0, attrZ: Float = 0
    private var attrV1: UInt32 = 0, attrV2: UInt32 = 0, attrV3: UInt32 = 0
    private var attrPaint: Int = 0
    private var attrTransform: String?
    private var attrPath: String?
    private var attrUnit: String?

    private func elementKind(bytes: UnsafePointer<UInt8>, start: Int, end: Int) -> ElementKind {
        // Compare against the element's local name (drop any namespace prefix).
        var s = start
        for j in start..<end where bytes[j] == UInt8(ascii: ":") { s = j + 1 }
        switch end - s {
        case 5 where eq(bytes, s, "model"): return .model
        case 6 where eq(bytes, s, "object"): return .object
        case 6 where eq(bytes, s, "vertex"): return .vertex
        case 8 where eq(bytes, s, "vertices"): return .vertices
        case 8 where eq(bytes, s, "triangle"): return .triangle
        case 9 where eq(bytes, s, "triangles"): return .triangles
        case 9 where eq(bytes, s, "component"): return .component
        case 10 where eq(bytes, s, "components"): return .components
        case 4 where eq(bytes, s, "item"): return .item
        default: return .other
        }
    }

    private func handleStart(_ kind: ElementKind) {
        switch kind {
        case .model:
            attrUnit = nil
        case .object:
            attrObjectId = nil
            attrType = nil
            currentVertices = []
            currentIndices = []
            currentPaintStates = []
            currentComponents = []
        case .vertices:
            inVertices = true
        case .vertex:
            attrX = 0; attrY = 0; attrZ = 0
        case .triangles:
            inTriangles = true
        case .triangle:
            attrV1 = 0; attrV2 = 0; attrV3 = 0; attrPaint = 0
        case .components:
            inComponents = true
        case .component:
            attrObjectId = nil; attrTransform = nil; attrPath = nil
        case .item:
            attrObjectId = nil; attrTransform = nil
        case .other:
            break
        }
    }

    private func handleAttribute(_ kind: ElementKind, bytes: UnsafePointer<UInt8>,
                                 nameStart: Int, nameEnd: Int, valueStart: Int, valueEnd: Int) {
        let nlen = nameEnd - nameStart
        switch kind {
        case .model:
            if nlen == 4 && eq(bytes, nameStart, "unit") {
                attrUnit = string(bytes, valueStart, valueEnd)
            }
        case .object:
            if nlen == 2 && eq(bytes, nameStart, "id") {
                attrObjectId = parseInt(bytes, valueStart, valueEnd)
            } else if nlen == 4 && eq(bytes, nameStart, "type") {
                attrType = string(bytes, valueStart, valueEnd)
            }
        case .vertex:
            guard parseMesh, nlen == 1 else { return }
            switch bytes[nameStart] {
            case UInt8(ascii: "x"): attrX = Self.finiteFloat(parseDouble(bytes, valueStart, valueEnd))
            case UInt8(ascii: "y"): attrY = Self.finiteFloat(parseDouble(bytes, valueStart, valueEnd))
            case UInt8(ascii: "z"): attrZ = Self.finiteFloat(parseDouble(bytes, valueStart, valueEnd))
            default: break
            }
        case .triangle:
            guard parseMesh else { return }
            if nlen == 2 && bytes[nameStart] == UInt8(ascii: "v") {
                switch bytes[nameStart + 1] {
                case UInt8(ascii: "1"): attrV1 = UInt32(truncatingIfNeeded: parseInt(bytes, valueStart, valueEnd) ?? 0)
                case UInt8(ascii: "2"): attrV2 = UInt32(truncatingIfNeeded: parseInt(bytes, valueStart, valueEnd) ?? 0)
                case UInt8(ascii: "3"): attrV3 = UInt32(truncatingIfNeeded: parseInt(bytes, valueStart, valueEnd) ?? 0)
                default: break
                }
            } else if nlen == 11 && eq(bytes, nameStart, "paint_color") {
                attrPaint = PaintColorDecoder.decode(string(bytes, valueStart, valueEnd))
            }
        case .component:
            if nlen == 8 && eq(bytes, nameStart, "objectid") {
                attrObjectId = parseInt(bytes, valueStart, valueEnd)
            } else if nlen == 9 && eq(bytes, nameStart, "transform") {
                attrTransform = string(bytes, valueStart, valueEnd)
            } else if localNameEquals(bytes, nameStart, nameEnd, "path") {
                attrPath = string(bytes, valueStart, valueEnd)
            }
        case .item:
            if nlen == 8 && eq(bytes, nameStart, "objectid") {
                attrObjectId = parseInt(bytes, valueStart, valueEnd)
            } else if nlen == 9 && eq(bytes, nameStart, "transform") {
                attrTransform = string(bytes, valueStart, valueEnd)
            }
        case .vertices, .triangles, .components, .other:
            break
        }
    }

    private func finishStart(_ kind: ElementKind) throws {
        switch kind {
        case .model:
            if let u = attrUnit, let parsed = LengthUnit(rawValue: u) { unit = parsed }
        case .object:
            currentObjectId = attrObjectId
            currentObjectType = attrType
        case .vertex:
            if parseMesh && inVertices { currentVertices.append(SIMD3(attrX, attrY, attrZ)) }
        case .triangle:
            if parseMesh && inTriangles {
                currentIndices.append(attrV1)
                currentIndices.append(attrV2)
                currentIndices.append(attrV3)
                currentPaintStates.append(attrPaint)
                totalTriangleCount += 1
                if let maxTriangles, totalTriangleCount > maxTriangles {
                    throw ThreeMFError.meshTooLarge(triangles: totalTriangleCount, limit: maxTriangles)
                }
            }
        case .component:
            if inComponents, let id = attrObjectId {
                currentComponents.append((objectId: id, transform: Matrix4.parse(attrTransform), path: attrPath))
            }
        case .item:
            if let id = attrObjectId {
                buildItems.append(BuildItem(objectId: id, transform: Matrix4.parse(attrTransform)))
            }
        case .vertices, .triangles, .components, .other:
            break
        }
    }

    private func handleEnd(bytes: UnsafePointer<UInt8>, start: Int, end: Int) {
        var s = start
        for j in start..<end where bytes[j] == UInt8(ascii: ":") { s = j + 1 }
        switch end - s {
        case 8 where eq(bytes, s, "vertices"): inVertices = false
        case 9 where eq(bytes, s, "triangles"): inTriangles = false
        case 10 where eq(bytes, s, "components"): inComponents = false
        case 6 where eq(bytes, s, "object"):
            guard let id = currentObjectId else { return }
            // Per the 3MF core spec, "support" (auto-generated print
            // supports) and "other" objects must not be rendered or counted;
            // "model" (default)/"solidsupport"/"surface" are kept.
            if currentObjectType == "support" || currentObjectType == "other" {
                objects[id] = .excluded
            } else if !currentComponents.isEmpty {
                objects[id] = .components(currentComponents)
            } else {
                // Vertices precede triangles inside a well-formed <mesh>, but
                // a malformed/adversarial file can still declare a triangle
                // index >= vertices.count; that must never reach the
                // renderer, so filter here (parallel with paint states).
                let sanitized = Self.sanitizedTriangleData(vertexCount: currentVertices.count, indices: currentIndices, paintStates: currentPaintStates)
                objects[id] = .mesh(TriangleMesh(positions: currentVertices, indices: sanitized.indices), paintStates: sanitized.paintStates)
            }
            currentObjectId = nil
            currentObjectType = nil
        default:
            break
        }
    }

    /// Drops triangles whose v1/v2/v3 is out of range for `vertexCount`,
    /// dropping the parallel `paintStates` entry too so counts stay aligned.
    /// The common case (nothing to drop) is a fast full-array scan with no
    /// allocation.
    private static func sanitizedTriangleData(vertexCount: Int, indices: [UInt32], paintStates: [Int]) -> (indices: [UInt32], paintStates: [Int]) {
        guard indices.contains(where: { Int($0) >= vertexCount }) else { return (indices, paintStates) }

        var keptIndices: [UInt32] = []
        keptIndices.reserveCapacity(indices.count)
        var keptPaintStates: [Int] = []
        keptPaintStates.reserveCapacity(paintStates.count)

        var triangle = 0
        var i = 0
        while i + 2 < indices.count {
            let i0 = indices[i], i1 = indices[i + 1], i2 = indices[i + 2]
            if Int(i0) < vertexCount, Int(i1) < vertexCount, Int(i2) < vertexCount {
                keptIndices.append(contentsOf: [i0, i1, i2])
                if triangle < paintStates.count { keptPaintStates.append(paintStates[triangle]) }
            }
            i += 3
            triangle += 1
        }
        return (keptIndices, keptPaintStates)
    }

    // MARK: - Byte helpers

    @inline(__always) private func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    @inline(__always) private func isNameEnd(_ b: UInt8) -> Bool {
        isSpace(b) || b == UInt8(ascii: ">") || b == UInt8(ascii: "/")
    }

    /// Byte-compares the region starting at `start` against `literal`.
    @inline(__always) private func eq(_ bytes: UnsafePointer<UInt8>, _ start: Int, _ literal: StaticString) -> Bool {
        literal.withUTF8Buffer { buf in
            for k in 0..<buf.count where bytes[start + k] != buf[k] { return false }
            return true
        }
    }

    /// Whether the local name (after any namespace prefix) equals `literal`.
    @inline(__always) private func localNameEquals(_ bytes: UnsafePointer<UInt8>, _ start: Int, _ end: Int, _ literal: StaticString) -> Bool {
        var s = start
        for j in start..<end where bytes[j] == UInt8(ascii: ":") { s = j + 1 }
        return (end - s) == literal.utf8CodeUnitCount && eq(bytes, s, literal)
    }

    @inline(__always) private func string(_ bytes: UnsafePointer<UInt8>, _ start: Int, _ end: Int) -> String {
        String(decoding: UnsafeBufferPointer(start: bytes + start, count: max(0, end - start)), as: UTF8.self)
    }

    /// Narrows a (already-finite) `Double` to `Float`, clamping the rare case
    /// where the `Double` is finite but exceeds `Float`'s range (the
    /// Double->Float conversion itself doesn't trap, but can produce ±inf,
    /// which must not poison the mesh's bounding box).
    @inline(__always) private static func finiteFloat(_ value: Double) -> Float {
        let narrowed = Float(value)
        return narrowed.isFinite ? narrowed : 0
    }

    /// Parses a base-10 integer from `bytes[start..<end]`, tolerating a leading
    /// sign and surrounding whitespace. Returns `nil` if no digits are present.
    /// Overflow-safe: 3MF ids/vertex indices fit comfortably in `UInt32`, so a
    /// pathological attribute (e.g. a 20-digit value) clamps to `Int.max`/
    /// `Int.min` instead of trapping on `value * 10 + digit`.
    @inline(__always) private func parseInt(_ bytes: UnsafePointer<UInt8>, _ start: Int, _ end: Int) -> Int? {
        var i = start
        while i < end && isSpace(bytes[i]) { i += 1 }
        var sign = 1
        if i < end && (bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+")) {
            if bytes[i] == UInt8(ascii: "-") { sign = -1 }
            i += 1
        }
        var value = 0
        var sawDigit = false
        var overflowed = false
        while i < end {
            let d = bytes[i]
            guard d >= UInt8(ascii: "0") && d <= UInt8(ascii: "9") else { break }
            sawDigit = true
            if !overflowed {
                if value > (Int.max - 9) / 10 {
                    overflowed = true
                    value = Int.max
                } else {
                    value = value * 10 + Int(d - UInt8(ascii: "0"))
                }
            }
            i += 1
        }
        guard sawDigit else { return nil }
        return overflowed ? (sign > 0 ? Int.max : Int.min) : sign * value
    }

    /// Parses a floating-point value from `bytes[start..<end]` (sign, integer
    /// part, fraction, and optional exponent). Always uses "." as the decimal
    /// separator, independent of the user's locale.
    @inline(__always) private func parseDouble(_ bytes: UnsafePointer<UInt8>, _ start: Int, _ end: Int) -> Double {
        let zero = UInt8(ascii: "0"), nine = UInt8(ascii: "9")
        var i = start
        while i < end && isSpace(bytes[i]) { i += 1 }
        var sign = 1.0
        if i < end && (bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+")) {
            if bytes[i] == UInt8(ascii: "-") { sign = -1.0 }
            i += 1
        }
        var result = 0.0
        while i < end, bytes[i] >= zero, bytes[i] <= nine {
            result = result * 10.0 + Double(bytes[i] - zero)
            i += 1
        }
        if i < end && bytes[i] == UInt8(ascii: ".") {
            i += 1
            var scale = 0.1
            while i < end, bytes[i] >= zero, bytes[i] <= nine {
                result += Double(bytes[i] - zero) * scale
                scale *= 0.1
                i += 1
            }
        }
        if i < end && (bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E")) {
            i += 1
            var expSign = 1
            if i < end && (bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+")) {
                if bytes[i] == UInt8(ascii: "-") { expSign = -1 }
                i += 1
            }
            var exp = 0
            while i < end, bytes[i] >= zero, bytes[i] <= nine {
                // Clamp accumulation so a pathological exponent (e.g.
                // "1e999999999") can't overflow `exp * 10 + digit`; `pow`
                // already saturates to inf/0 well before 400 anyway.
                if exp < 10_000 { exp = exp * 10 + Int(bytes[i] - zero) }
                i += 1
            }
            if exp != 0 {
                result *= pow(10.0, Double(expSign * min(exp, 400)))
            }
        }
        let final = sign * result
        // A non-finite coordinate (from an extreme exponent, or otherwise)
        // must not poison the mesh's bounding box; treat it as 0 rather than
        // dropping the vertex (which would shift every later triangle index).
        return final.isFinite ? final : 0
    }
}
