import Foundation

/// Loads `.3mf` packages (OPC/ZIP archives) into a `ThreeMFDocument`.
public struct ThreeMFLoader {
    public struct Options {
        public var parseMesh: Bool
        public var parsePlates: Bool
        public var maxModelPartBytes: Int
        public var maxThumbnailBytes: Int

        public init(
            parseMesh: Bool = true,
            parsePlates: Bool = true,
            maxModelPartBytes: Int = 500 * 1024 * 1024,
            maxThumbnailBytes: Int = 20 * 1024 * 1024
        ) {
            self.parseMesh = parseMesh
            self.parsePlates = parsePlates
            self.maxModelPartBytes = maxModelPartBytes
            self.maxThumbnailBytes = maxThumbnailBytes
        }

        public static var `default`: Options { Options() }
        public static var thumbnailOnly: Options { Options(parseMesh: false) }
    }

    private let options: Options

    public init(options: Options = .default) {
        self.options = options
    }

    public func load(url: URL) throws -> ThreeMFDocument {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try load(data: data)
    }

    public func load(data: Data) throws -> ThreeMFDocument {
        let zip = try ZipArchive(data: data)

        let modelPath = try resolveModelPartPath(in: zip)
        guard let modelData = try zip.dataCaseInsensitive(for: modelPath, sizeLimit: options.maxModelPartBytes) else {
            throw ThreeMFError.missingModelPart
        }

        let model = try ModelXMLParser.parse(data: modelData, parseMesh: options.parseMesh)

        var plateAssignments: [BambuPlateAssignment] = []
        var objectExtruder: [Int: Int] = [:]
        if options.parsePlates, let settingsData = try zip.dataCaseInsensitive(for: "Metadata/model_settings.config") {
            if let parsed = try? BambuModelSettingsParser.parse(data: settingsData) {
                plateAssignments = parsed.plates
                objectExtruder = parsed.objectExtruder
            }
        }

        // Production Extension packages keep object geometry in separate
        // model parts, referenced from `<component p:path="...">`. Lazily
        // parse and cache those external parts as the resolver requests them.
        var partCache: [String: [Int: ObjectDefinition]] = [:]
        let provider: MeshResolver.PartProvider = { partPath in
            guard let partPath else { return model.objects } // root part
            if let cached = partCache[partPath] { return cached }
            guard let partData = try zip.dataCaseInsensitive(for: partPath, sizeLimit: options.maxModelPartBytes) else { return [:] }
            let parsed = try ModelXMLParser.parse(data: partData, parseMesh: options.parseMesh)
            partCache[partPath] = parsed.objects
            return parsed.objects
        }
        let resolvedItems = try MeshResolver.resolveBuildItems(buildItems: model.buildItems, provider: provider, objectExtruder: objectExtruder)

        let packageThumbnail = try loadPackageThumbnail(zip: zip)

        var projectColors: [String]? = nil
        var projectTypes: [String]? = nil
        if let projectData = try zip.dataCaseInsensitive(for: "Metadata/project_settings.config") {
            let parsed = BambuPlateStatsParser.parseProjectSettings(data: projectData)
            projectColors = parsed.colors
            projectTypes = parsed.types
        }
        let palette = projectColors ?? []

        let plates: [BuildPlate]
        if !plateAssignments.isEmpty {
            plates = try buildBambuPlates(
                assignments: plateAssignments,
                resolvedItems: resolvedItems,
                zip: zip,
                projectColors: projectColors,
                projectTypes: projectTypes,
                palette: palette
            )
        } else {
            plates = [try buildImplicitPlate(resolvedItems: resolvedItems, zip: zip, packageThumbnail: packageThumbnail, palette: palette)]
        }

        return ThreeMFDocument(unit: model.unit, plates: plates.sorted { $0.id < $1.id }, packageThumbnail: packageThumbnail)
    }

    // MARK: - Thumbnails

    public func extractPrimaryThumbnail(url: URL) throws -> Data? {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try extractPrimaryThumbnail(data: data)
    }

    public func extractPrimaryThumbnail(data: Data) throws -> Data? {
        let zip = try ZipArchive(data: data)
        let candidates = [
            "Metadata/plate_1.png",
            "Metadata/thumbnail.png",
            "Metadata/top_1.png",
            "thumbnail/thumbnail.png",
            "3D/Metadata/thumbnail.png"
        ]
        for candidate in candidates {
            if let data = try zip.dataCaseInsensitive(for: candidate, sizeLimit: options.maxThumbnailBytes) {
                return data
            }
        }
        return nil
    }

    // MARK: - Internals

    private func resolveModelPartPath(in zip: ZipArchive) throws -> String {
        if let relsData = try zip.data(for: "_rels/.rels"),
           let rels = try? OPCRelationships.parse(data: relsData),
           let modelPath = rels.modelPartPath {
            return modelPath
        }
        let fallbacks = ["3D/3dmodel.model", "3D/3DModel.model", "3d/3dmodel.model"]
        for fallback in fallbacks {
            let lower = fallback.lowercased()
            if zip.entryPaths.contains(where: { $0.lowercased() == lower }) {
                return fallback
            }
        }
        throw ThreeMFError.missingModelPart
    }

    private func loadPackageThumbnail(zip: ZipArchive) throws -> Data? {
        if let relsData = try zip.data(for: "_rels/.rels"),
           let rels = try? OPCRelationships.parse(data: relsData),
           let thumbPath = rels.thumbnailPartPath {
            if let data = try zip.dataCaseInsensitive(for: thumbPath, sizeLimit: options.maxThumbnailBytes) {
                return data
            }
        }
        return try zip.dataCaseInsensitive(for: "Metadata/thumbnail.png", sizeLimit: options.maxThumbnailBytes)
    }

    private func buildImplicitPlate(resolvedItems: [(objectId: Int, mesh: TriangleMesh)], zip: ZipArchive, packageThumbnail: Data?, palette: [String]) throws -> BuildPlate {
        var mesh = TriangleMesh()
        for item in resolvedItems {
            mesh.append(item.mesh)
        }
        mesh = Self.finalizeMesh(mesh, hasPalette: !palette.isEmpty)
        let thumbnail = try zip.dataCaseInsensitive(for: "Metadata/plate_1.png", sizeLimit: options.maxThumbnailBytes) ?? packageThumbnail
        var stats: PlateStats? = nil
        if let statsData = try zip.dataCaseInsensitive(for: "Metadata/plate_1.json") {
            stats = BambuPlateStatsParser.parseStats(json: statsData, colors: nil, types: nil)
        }
        return BuildPlate(id: 1, name: "Plate 1", thumbnail: thumbnail, mesh: mesh, stats: stats, palette: palette)
    }

    private func buildBambuPlates(
        assignments: [BambuPlateAssignment],
        resolvedItems: [(objectId: Int, mesh: TriangleMesh)],
        zip: ZipArchive,
        projectColors: [String]?,
        projectTypes: [String]?,
        palette: [String]
    ) throws -> [BuildPlate] {
        var meshByObjectId: [Int: TriangleMesh] = [:]
        for item in resolvedItems {
            if var existing = meshByObjectId[item.objectId] {
                existing.append(item.mesh)
                meshByObjectId[item.objectId] = existing
            } else {
                meshByObjectId[item.objectId] = item.mesh
            }
        }

        var plates: [BuildPlate] = []
        for assignment in assignments {
            var mesh = TriangleMesh()
            for objectId in assignment.objectIds {
                if let objMesh = meshByObjectId[objectId] {
                    mesh.append(objMesh)
                }
            }
            mesh = Self.finalizeMesh(mesh, hasPalette: !palette.isEmpty)

            let thumbnail = try zip.dataCaseInsensitive(for: "Metadata/plate_\(assignment.id).png", sizeLimit: options.maxThumbnailBytes)

            var stats: PlateStats? = nil
            if let statsData = try zip.dataCaseInsensitive(for: "Metadata/plate_\(assignment.id).json") {
                stats = BambuPlateStatsParser.parseStats(json: statsData, colors: projectColors, types: projectTypes)
            }

            plates.append(BuildPlate(id: assignment.id, name: assignment.name, thumbnail: thumbnail, mesh: mesh, stats: stats, palette: palette))
        }
        return plates
    }

    /// Clears `triangleColorIndices` back to `nil` (uncolored) when there is no
    /// real color information: no filament palette *and* every triangle's
    /// resolved index is the default `0` (i.e. no `paint_color` overrides and
    /// no non-default base extruder were involved). This keeps plain/non-Bambu
    /// packages rendering as a single neutral material, unchanged from before.
    private static func finalizeMesh(_ mesh: TriangleMesh, hasPalette: Bool) -> TriangleMesh {
        guard let colorIndices = mesh.triangleColorIndices else { return mesh }
        guard hasPalette || !colorIndices.allSatisfy({ $0 == 0 }) else {
            var uncolored = mesh
            uncolored.triangleColorIndices = nil
            return uncolored
        }
        return mesh
    }
}
