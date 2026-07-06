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
}

/// A parsed `<item>` from `<build>`.
struct BuildItem {
    let objectId: Int
    let transform: Matrix4
}

/// SAX parser for the 3MF core schema (`3D/3dmodel.model`).
final class ModelXMLParser: NSObject, XMLParserDelegate {
    private(set) var unit: LengthUnit = .millimeter
    private(set) var objects: [Int: ObjectDefinition] = [:]
    private(set) var buildItems: [BuildItem] = []

    private var parseError: ThreeMFError?
    private let parseMesh: Bool

    // Parsing state.
    private var currentObjectId: Int?
    private var currentVertices: [SIMD3<Float>] = []
    private var currentIndices: [UInt32] = []
    private var currentPaintStates: [Int] = []
    private var currentComponents: [(objectId: Int, transform: Matrix4, path: String?)] = []
    private var inMesh = false
    private var inVertices = false
    private var inTriangles = false
    private var inComponents = false

    init(parseMesh: Bool) {
        self.parseMesh = parseMesh
    }

    static func parse(data: Data, parseMesh: Bool) throws -> ModelXMLParser {
        let delegate = ModelXMLParser(parseMesh: parseMesh)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            if let err = delegate.parseError { throw err }
            let message = parser.parserError.map { "\($0)" } ?? "unknown XML parse failure"
            throw ThreeMFError.malformedXML(message)
        }
        if let err = delegate.parseError { throw err }
        return delegate
    }

    private static func localName(_ qualified: String) -> String {
        guard let colonIndex = qualified.lastIndex(of: ":") else { return qualified }
        return String(qualified[qualified.index(after: colonIndex)...])
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName)
        switch name {
        case "model":
            if let unitString = attributeDict["unit"], let parsedUnit = LengthUnit(rawValue: unitString) {
                unit = parsedUnit
            }
        case "object":
            guard let idString = attributeDict["id"], let id = Int(idString) else { return }
            currentObjectId = id
            currentVertices = []
            currentIndices = []
            currentPaintStates = []
            currentComponents = []
        case "mesh":
            inMesh = true
        case "vertices":
            inVertices = true
        case "vertex":
            guard inVertices, parseMesh else { return }
            let x = Float(attributeDict["x"] ?? "") ?? 0
            let y = Float(attributeDict["y"] ?? "") ?? 0
            let z = Float(attributeDict["z"] ?? "") ?? 0
            currentVertices.append(SIMD3(x, y, z))
        case "triangles":
            inTriangles = true
        case "triangle":
            guard inTriangles, parseMesh else { return }
            guard let v1 = UInt32(attributeDict["v1"] ?? ""),
                  let v2 = UInt32(attributeDict["v2"] ?? ""),
                  let v3 = UInt32(attributeDict["v3"] ?? "") else { return }
            currentIndices.append(contentsOf: [v1, v2, v3])
            let paintState = attributeDict["paint_color"].map { PaintColorDecoder.decode($0) } ?? 0
            currentPaintStates.append(paintState)
        case "components":
            inComponents = true
        case "component":
            guard inComponents, let idString = attributeDict["objectid"], let id = Int(idString) else { return }
            let transform = Matrix4.parse(attributeDict["transform"])
            // Production Extension path: normally keyed as "p:path" (namespace
            // processing is disabled), but fall back to scanning for any
            // attribute whose local name is "path" in case a different prefix
            // was used for the production namespace.
            let path = attributeDict["p:path"] ?? attributeDict.first(where: { Self.localName($0.key) == "path" })?.value
            currentComponents.append((objectId: id, transform: transform, path: path))
        case "item":
            guard let idString = attributeDict["objectid"], let id = Int(idString) else { return }
            let transform = Matrix4.parse(attributeDict["transform"])
            buildItems.append(BuildItem(objectId: id, transform: transform))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        switch name {
        case "vertices":
            inVertices = false
        case "triangles":
            inTriangles = false
        case "components":
            inComponents = false
        case "mesh":
            inMesh = false
        case "object":
            guard let id = currentObjectId else { return }
            if !currentComponents.isEmpty {
                objects[id] = .components(currentComponents)
            } else {
                objects[id] = .mesh(TriangleMesh(positions: currentVertices, indices: currentIndices), paintStates: currentPaintStates)
            }
            currentObjectId = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if self.parseError == nil {
            self.parseError = .malformedXML(parseError.localizedDescription)
        }
    }
}
