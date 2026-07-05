import Foundation

/// One `<plate>` block parsed from `Metadata/model_settings.config`.
struct BambuPlateAssignment {
    let id: Int
    let name: String
    /// Build-item object ids (`model_instance/metadata[@key="object_id"]`) assigned to this plate.
    let objectIds: [Int]
}

/// Parses Bambu/Orca `Metadata/model_settings.config` (an XML `<config>` document).
enum BambuModelSettingsParser {
    static func parse(data: Data) throws -> [BambuPlateAssignment] {
        let delegate = ModelSettingsXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            let message = parser.parserError.map { "\($0)" } ?? "unknown XML parse failure"
            throw ThreeMFError.malformedXML(message)
        }
        return delegate.plates
    }
}

private final class ModelSettingsXMLParser: NSObject, XMLParserDelegate {
    var plates: [BambuPlateAssignment] = []

    private var inPlate = false
    private var inModelInstance = false
    private var platerId: Int?
    private var platerName: String = ""
    private var objectIds: [Int] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "plate":
            inPlate = true
            platerId = nil
            platerName = ""
            objectIds = []
        case "model_instance":
            inModelInstance = true
        case "metadata":
            guard inPlate, let key = attributeDict["key"] else { return }
            let value = attributeDict["value"] ?? ""
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
        default:
            break
        }
    }
}
