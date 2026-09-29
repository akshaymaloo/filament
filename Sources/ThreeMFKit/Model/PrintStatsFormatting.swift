import Foundation

/// Shared formatting helpers for print statistics (duration, weight,
/// dimensions, triangle counts) and filament color hex strings. Used by both
/// the main app's `PrintStatsFormatter` and the Quick Look preview
/// extension so their displayed text stays byte-identical.
public enum PrintStatsFormatting {
    /// Locale pinned to `en_US_POSIX` (rather than the host's current
    /// locale) so grouped output is deterministic across machines/CI, e.g.
    /// always "12,345 triangles" and never a locale-specific variant.
    private static let groupedInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// Formats a duration as "Xh Ym" (hours omitted when zero). Negative
    /// input is clamped to zero.
    public static func duration(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    public static func weight(grams: Double) -> String {
        String(format: "%.1f g", grams)
    }

    /// Formats a mesh's bounding box as "W × D × H mm", converting from the
    /// document's declared length unit into millimeters. Returns `nil` for an
    /// empty mesh (no bounding box).
    public static func dimensions(for mesh: TriangleMesh, unit: LengthUnit) -> String? {
        guard let box = mesh.boundingBox else { return nil }
        let mmPerUnit = Float(unit.millimetersPerUnit)
        let size = box.max - box.min
        let width = size.x * mmPerUnit
        let depth = size.y * mmPerUnit
        let height = size.z * mmPerUnit
        return String(format: "%.1f × %.1f × %.1f mm", width, depth, height)
    }

    /// Formats a triangle count with thousands separators, e.g. "12,345 triangles".
    public static func triangleCount(_ count: Int) -> String {
        let formatted = groupedInteger.string(from: NSNumber(value: count)) ?? "\(count)"
        return count == 1 ? "\(formatted) triangle" : "\(formatted) triangles"
    }

    /// Parses a `"#RRGGBB"`/`"#RRGGBBAA"` (leading `#` optional, surrounding
    /// whitespace trimmed) filament color hex string into normalized RGBA
    /// components in `[0, 1]`. Returns `nil` for `nil` input or any string
    /// that isn't exactly 6 or 8 hex digits.
    public static func rgba(fromHex hex: String?) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard let hex else { return nil }
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }
        guard sanitized.count == 6 || sanitized.count == 8, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }
        let hasAlpha = sanitized.count == 8
        let r, g, b, a: UInt32
        if hasAlpha {
            r = (value >> 24) & 0xFF
            g = (value >> 16) & 0xFF
            b = (value >> 8) & 0xFF
            a = value & 0xFF
        } else {
            r = (value >> 16) & 0xFF
            g = (value >> 8) & 0xFF
            b = value & 0xFF
            a = 0xFF
        }
        return (
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            alpha: Double(a) / 255.0
        )
    }
}
