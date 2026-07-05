import AppKit
import SwiftUI
import ThreeMFKit

/// Small formatting helpers shared by the info panel and plate overlays.
enum PrintStatsFormatter {
    static func duration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func weight(grams: Double) -> String {
        String(format: "%.1f g", grams)
    }

    /// Formats a mesh's bounding box as "W × D × H mm", converting from the
    /// document's declared length unit into millimeters. Returns `nil` for an
    /// empty mesh (no bounding box).
    static func dimensions(for mesh: TriangleMesh, unit: LengthUnit) -> String? {
        guard let box = mesh.boundingBox else { return nil }
        let mmPerUnit = Float(unit.millimetersPerUnit)
        let size = box.max - box.min
        let width = size.x * mmPerUnit
        let depth = size.y * mmPerUnit
        let height = size.z * mmPerUnit
        return String(format: "%.1f × %.1f × %.1f mm", width, depth, height)
    }

    /// Formats a triangle count with thousands separators, e.g. "12,345 triangles".
    static func triangleCount(_ count: Int) -> String {
        let formatted = Formatter.groupedInteger.string(from: NSNumber(value: count)) ?? "\(count)"
        return count == 1 ? "\(formatted) triangle" : "\(formatted) triangles"
    }

    static func color(fromHex hex: String?) -> Color? {
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
        return Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

private extension Formatter {
    static let groupedInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}
