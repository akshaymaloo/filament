import AppKit
import SwiftUI
import ThreeMFKit

/// Small formatting helpers shared by the info panel and plate overlays.
/// Thin wrapper around `ThreeMFKit.PrintStatsFormatting`, so the app and the
/// Quick Look preview extension render byte-identical text.
enum PrintStatsFormatter {
    static func duration(seconds: Int) -> String {
        PrintStatsFormatting.duration(seconds: seconds)
    }

    static func weight(grams: Double) -> String {
        PrintStatsFormatting.weight(grams: grams)
    }

    static func dimensions(for mesh: TriangleMesh, unit: LengthUnit) -> String? {
        PrintStatsFormatting.dimensions(for: mesh, unit: unit)
    }

    static func triangleCount(_ count: Int) -> String {
        PrintStatsFormatting.triangleCount(count)
    }

    static func color(fromHex hex: String?) -> Color? {
        guard let rgba = PrintStatsFormatting.rgba(fromHex: hex) else { return nil }
        return Color(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
