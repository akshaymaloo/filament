import Foundation

/// The base length unit declared on the 3MF `<model unit="...">` attribute.
public enum LengthUnit: String {
    case micron
    case millimeter
    case centimeter
    case inch
    case foot
    case meter
}

public extension LengthUnit {
    /// Conversion factor to millimeters.
    var millimetersPerUnit: Double {
        switch self {
        case .micron: return 0.001
        case .millimeter: return 1
        case .centimeter: return 10
        case .inch: return 25.4
        case .foot: return 304.8
        case .meter: return 1000
        }
    }
}
