import Foundation

/// Parsed OPC relationships from a `.rels` part.
struct OPCRelationships {
    /// Zip entry path (leading `/` stripped) of the 3D model start part, if declared.
    let modelPartPath: String?
    /// Zip entry path of the package thumbnail, if declared.
    let thumbnailPartPath: String?

    private static let modelRelationshipType = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    private static let thumbnailRelationshipType = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"

    static func parse(data: Data) throws -> OPCRelationships {
        let delegate = RelationshipsXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            let message = parser.parserError.map { "\($0)" } ?? "unknown XML parse failure"
            throw ThreeMFError.malformedXML(message)
        }
        return OPCRelationships(
            modelPartPath: delegate.relationships[modelRelationshipType].map(Self.normalize),
            thumbnailPartPath: delegate.relationships[thumbnailRelationshipType].map(Self.normalize)
        )
    }

    private static func normalize(_ target: String) -> String {
        target.hasPrefix("/") ? String(target.dropFirst()) : target
    }
}

private final class RelationshipsXMLParser: NSObject, XMLParserDelegate {
    /// Relationship Type -> Target, last one wins if duplicated.
    var relationships: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.contains(":") ? String(elementName.split(separator: ":").last!) : elementName
        guard name == "Relationship" else { return }
        guard let type = attributeDict["Type"], let target = attributeDict["Target"] else { return }
        relationships[type] = target
    }
}
