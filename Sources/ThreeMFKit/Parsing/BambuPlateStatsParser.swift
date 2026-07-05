import Foundation

/// Parses Bambu/Orca per-plate JSON metadata (`Metadata/plate_<id>.json`) and,
/// optionally, project-level filament colors (`Metadata/project_settings.config`,
/// which despite its extension is a JSON document).
enum BambuPlateStatsParser {
    static func parseStats(json data: Data, colors: [String]?, types: [String]?) -> PlateStats? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        let prediction = intValue(object["prediction"])
        let weight = doubleValue(object["weight"])
        let printerModel = stringValue(object["printer_model_id"]) ?? stringValue(object["machine_id"])

        let usedGrams = doubleArray(object["filament_used_g"]) ?? doubleArray(object["filament_weight"])
        let plateColors = stringArray(object["filament_colors"]) ?? colors
        let plateTypes = stringArray(object["filament_types"]) ?? types

        var filaments: [FilamentUsage] = []
        let count = max(usedGrams?.count ?? 0, max(plateColors?.count ?? 0, plateTypes?.count ?? 0))
        if count > 0 {
            for i in 0..<count {
                filaments.append(FilamentUsage(
                    type: plateTypes.flatMap { i < $0.count ? $0[i] : nil },
                    colorHex: plateColors.flatMap { i < $0.count ? $0[i] : nil },
                    usedGrams: usedGrams.flatMap { i < $0.count ? $0[i] : nil },
                    usedMeters: nil
                ))
            }
        }

        return PlateStats(predictionSeconds: prediction, weightGrams: weight, printerModel: printerModel, filaments: filaments)
    }

    /// Reads `filament_colour` (and `filament_type`, if present) from a project settings JSON blob.
    static func parseProjectSettings(data: Data) -> (colors: [String]?, types: [String]?) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (nil, nil)
        }
        return (stringArray(object["filament_colour"]), stringArray(object["filament_type"]))
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? Double { return n }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func stringValue(_ any: Any?) -> String? {
        any as? String
    }

    private static func doubleArray(_ any: Any?) -> [Double]? {
        guard let array = any as? [Any] else { return nil }
        return array.map { doubleValue($0) ?? 0 }
    }

    private static func stringArray(_ any: Any?) -> [String]? {
        any as? [String]
    }
}
