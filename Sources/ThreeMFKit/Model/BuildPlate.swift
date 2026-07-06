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
    /// Filament colors as `"#RRGGBB"`/`"#RRGGBBAA"` hex strings, from the
    /// slicer's `filament_colour` project setting. Index `i` is the color for
    /// palette index `i` in `mesh.triangleColorIndices` (extruder `i + 1`).
    /// Empty when the source package has no known filament palette.
    public let palette: [String]

    public init(id: Int, name: String, thumbnail: Data?, mesh: TriangleMesh, stats: PlateStats?, palette: [String] = []) {
        self.id = id
        self.name = name
        self.thumbnail = thumbnail
        self.mesh = mesh
        self.stats = stats
        self.palette = palette
    }

    /// Whether this plate carries renderable multi-color data: a palette of at
    /// least two filaments plus per-triangle color assignments that span more
    /// than one color. Hosts use this to decide whether to offer a
    /// color/monochrome toggle (there's nothing to toggle for a single color).
    public var hasColorData: Bool {
        guard palette.count >= 2, let indices = mesh.triangleColorIndices, let first = indices.first else {
            return false
        }
        return indices.contains { $0 != first }
    }
}
