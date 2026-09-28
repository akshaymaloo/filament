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
    /// The mesh exceeds a caller-supplied `maxTriangles` budget.
    case meshTooLarge(triangles: Int, limit: Int)
    /// Loading was aborted by a caller-supplied `shouldCancel` check.
    case cancelled
    /// The sum of every extracted (uncompressed) entry in the archive
    /// exceeded a caller-supplied `maxTotalUncompressedBytes` budget.
    case archiveTooLarge(limit: Int)

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
        case .meshTooLarge(let triangles, let limit):
            return "Mesh has too many triangles (\(triangles), limit \(limit))."
        case .cancelled:
            return "Loading was cancelled."
        case .archiveTooLarge(let limit):
            return "Archive's total uncompressed content exceeds the size limit (\(limit) bytes)."
        }
    }
}
