import Foundation

/// Supported on-disk 3D model formats that `ModelLoader` can dispatch to.
public enum ModelFormat: String, CaseIterable {
    case threeMF = "3mf"
    case stl
    case obj
    case ply

    /// Case-insensitive lookup by file extension (leading "." is stripped).
    public init?(fileExtension ext: String) {
        var normalized = ext.lowercased()
        if normalized.hasPrefix(".") {
            normalized.removeFirst()
        }
        guard let match = ModelFormat(rawValue: normalized) else { return nil }
        self = match
    }

    public static var supportedExtensions: [String] {
        allCases.map { $0.rawValue }
    }
}

/// Facade that dispatches loading to the right parser (3MF package or a
/// single-mesh STL/OBJ/PLY file) based on file extension, falling back to
/// content sniffing when the extension is missing or unrecognized.
public struct ModelLoader {
    private let options: ThreeMFLoader.Options
    private let threeMFLoader: ThreeMFLoader

    public init(options: ThreeMFLoader.Options = .default) {
        self.options = options
        self.threeMFLoader = ThreeMFLoader(options: options)
    }

    public func load(url: URL) throws -> ThreeMFDocument {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let format = try ModelFormat(fileExtension: url.pathExtension) ?? sniffFormat(data: data)
        let name = url.deletingPathExtension().lastPathComponent
        return try load(data: data, format: format, name: name)
    }

    /// In-memory variant used by tests/validate: parses `data` as `format`
    /// and wraps the result in a `ThreeMFDocument`. For `.threeMF`, `name` is
    /// ignored (the document supplies its own plate names/metadata).
    public func load(data: Data, format: ModelFormat, name: String) throws -> ThreeMFDocument {
        switch format {
        case .threeMF:
            return try threeMFLoader.load(data: data)
        case .stl, .obj, .ply:
            let mesh: TriangleMesh
            if options.parseMesh {
                mesh = try parseMesh(data: data, format: format)
            } else {
                mesh = TriangleMesh()
            }
            let plate = BuildPlate(id: 1, name: name, thumbnail: nil, mesh: mesh, stats: nil)
            return ThreeMFDocument(unit: .millimeter, plates: [plate], packageThumbnail: nil)
        }
    }

    /// STL/OBJ/PLY files carry no embedded thumbnail; 3MF packages may.
    public func extractPrimaryThumbnail(url: URL) throws -> Data? {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let format = try ModelFormat(fileExtension: url.pathExtension) ?? sniffFormat(data: data)
        switch format {
        case .threeMF:
            return try threeMFLoader.extractPrimaryThumbnail(data: data)
        case .stl, .obj, .ply:
            return nil
        }
    }

    private func parseMesh(data: Data, format: ModelFormat) throws -> TriangleMesh {
        switch format {
        case .stl:
            return try STLParser.parse(data: data)
        case .obj:
            return try OBJParser.parse(data: data)
        case .ply:
            return try PLYParser.parse(data: data)
        case .threeMF:
            // Unreachable: callers only route here for the mesh-only formats.
            return TriangleMesh()
        }
    }

    /// Best-effort content sniffing when the file extension is missing or
    /// unrecognized: 3MF packages are ZIP archives, PLY files declare
    /// themselves with a "ply" magic line, binary STL files have an exact
    /// `84 + 50*count` byte layout (or start with "solid" for ascii), and
    /// OBJ files are plain text containing `v `/`f ` directives.
    private func sniffFormat(data: Data) throws -> ModelFormat {
        if data.count >= 4 {
            let signature = data.prefix(4)
            if signature.elementsEqual([0x50, 0x4B, 0x03, 0x04]) {
                return .threeMF
            }
        }
        if let prefix = String(data: data.prefix(3), encoding: .utf8), prefix.lowercased() == "ply" {
            return .ply
        }
        if data.count >= 84 {
            let reader = ByteReader(data)
            if let count = try? reader.u32(80), 84 + Int(count) * 50 == data.count {
                return .stl
            }
        }
        if let prefix = String(data: data.prefix(512), encoding: .utf8) {
            let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("solid") {
                return .stl
            }
        }
        if let text = String(data: data, encoding: .utf8) {
            let hasVertexLine = text.split(separator: "\n").contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("v ") || trimmed.hasPrefix("f ")
            }
            if hasVertexLine {
                return .obj
            }
        }
        throw ThreeMFError.malformedMesh("Unable to determine model format from file content.")
    }
}
