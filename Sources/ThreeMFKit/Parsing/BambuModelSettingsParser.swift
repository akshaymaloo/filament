import Foundation

/// One `<plate>` block parsed from `Metadata/model_settings.config`.
struct BambuPlateAssignment {
    let id: Int
    let name: String
    /// Build-item object ids (`model_instance/metadata[@key="object_id"]`) assigned to this plate.
    let objectIds: [Int]
}

/// Result of parsing `Metadata/model_settings.config`.
struct BambuModelSettings {
    let plates: [BambuPlateAssignment]
    /// Maps object id -> 1-based base extruder, from top-level
    /// `<object id="N"><metadata key="extruder" value="E"/></object>` blocks.
    /// Objects absent from this map default to extruder 1.
    let objectExtruder: [Int: Int]
}

/// Parses Bambu/Orca `Metadata/model_settings.config` (an XML `<config>` document).
enum BambuModelSettingsParser {
    static func parse(data: Data) throws -> BambuModelSettings {
        let delegate = ModelSettingsXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            let message = parser.parserError.map { "\($0)" } ?? "unknown XML parse failure"
            throw ThreeMFError.malformedXML(message)
        }
        return BambuModelSettings(plates: delegate.plates, objectExtruder: delegate.objectExtruder)
    }
}

private final class ModelSettingsXMLParser: NSObject, XMLParserDelegate {
    var plates: [BambuPlateAssignment] = []
    var objectExtruder: [Int: Int] = [:]

    private var inPlate = false
    private var inModelInstance = false
    private var platerId: Int?
    private var platerName: String = ""
    private var objectIds: [Int] = []

    // Top-level `<object id="N">` blocks (siblings of `<plate>`) carry
    // per-object metadata such as the base extruder.
    private var inObject = false
    private var currentObjectId: Int?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "plate":
            inPlate = true
            platerId = nil
            platerName = ""
            objectIds = []
        case "object":
            guard let idString = attributeDict["id"], let id = Int(idString) else { return }
            inObject = true
            currentObjectId = id
        case "model_instance":
            inModelInstance = true
        case "metadata":
            guard let key = attributeDict["key"] else { return }
            let value = attributeDict["value"] ?? ""
            if inPlate {
                if inModelInstance {
                    if key == "object_id", let id = Int(value) {
                        objectIds.append(id)
                    }
                } else {
                    if key == "plater_id", let id = Int(value) {
                        platerId = id
                    } else if key == "plater_name" {
                        platerName = value
                    }
                }
            } else if inObject, let objectId = currentObjectId {
                if key == "extruder", let extruder = Int(value) {
                    objectExtruder[objectId] = extruder
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "model_instance":
            inModelInstance = false
        case "plate":
            if let id = platerId {
                let name = platerName.trimmingCharacters(in: .whitespaces).isEmpty ? "Plate \(id)" : platerName
                plates.append(BambuPlateAssignment(id: id, name: name, objectIds: objectIds))
            }
            inPlate = false
        case "object":
            inObject = false
            currentObjectId = nil
        default:
            break
        }
    }
}
