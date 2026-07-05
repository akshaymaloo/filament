import Foundation

public enum ThreeMFError: Error, CustomStringConvertible {
    case notAZipArchive
    case missingModelPart
    case malformedXML(String)
    case entryTooLarge(path: String, size: Int, limit: Int)
    case unsupportedCompression(method: UInt16)
    case corruptArchive(String)
    /// A non-3MF mesh format (STL/OBJ/PLY) failed to parse, or the input
    /// format could not be determined.
    case malformedMesh(String)

    public var description: String {
        switch self {
        case .notAZipArchive:
            return "The file is not a valid ZIP/OPC archive."
        case .missingModelPart:
            return "No 3D model part could be located inside the archive."
        case .malformedXML(let detail):
            return "Malformed XML: \(detail)"
        case .entryTooLarge(let path, let size, let limit):
            return "Archive entry '\(path)' is too large (\(size) bytes, limit \(limit))."
        case .unsupportedCompression(let method):
            return "Unsupported ZIP compression method (\(method))."
        case .corruptArchive(let detail):
            return "Corrupt ZIP archive: \(detail)"
        case .malformedMesh(let detail):
            return "Malformed mesh data: \(detail)"
        }
    }
}
