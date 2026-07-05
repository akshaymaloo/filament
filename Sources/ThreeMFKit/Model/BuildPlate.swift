import Foundation

/// Per-filament usage statistics for a single build plate, as reported by
/// Bambu/Orca slicer plate metadata (e.g. `Metadata/plate_<id>.json`).
public struct FilamentUsage {
    public let type: String?
    public let colorHex: String?
    public let usedGrams: Double?
    public let usedMeters: Double?

    public init(type: String? = nil, colorHex: String? = nil, usedGrams: Double? = nil, usedMeters: Double? = nil) {
        self.type = type
        self.colorHex = colorHex
        self.usedGrams = usedGrams
        self.usedMeters = usedMeters
    }
}

/// Slicer-provided statistics for a single build plate.
public struct PlateStats {
    public let predictionSeconds: Int?
    public let weightGrams: Double?
    public let printerModel: String?
    public let filaments: [FilamentUsage]

    public init(predictionSeconds: Int? = nil, weightGrams: Double? = nil, printerModel: String? = nil, filaments: [FilamentUsage] = []) {
        self.predictionSeconds = predictionSeconds
        self.weightGrams = weightGrams
        self.printerModel = printerModel
        self.filaments = filaments
    }
}

/// A single build plate, containing the combined geometry of every object
/// assigned to it plus any slicer-provided thumbnail/statistics.
public struct BuildPlate: Identifiable {
    /// 1-based plate id (`plater_id`), or 1 for a non-Bambu implicit single plate.
    public let id: Int
    public let name: String
    public let thumbnail: Data?
    public let mesh: TriangleMesh
    public let stats: PlateStats?

    public init(id: Int, name: String, thumbnail: Data?, mesh: TriangleMesh, stats: PlateStats?) {
        self.id = id
        self.name = name
        self.thumbnail = thumbnail
        self.mesh = mesh
        self.stats = stats
    }
}
