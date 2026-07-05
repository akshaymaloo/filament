import Foundation

/// A parsed 3MF document: build plates, plate/package thumbnails, and length unit.
public struct ThreeMFDocument {
    public let unit: LengthUnit
    /// Always non-empty; sorted ascending by `id`.
    public let plates: [BuildPlate]
    /// The OPC-standard package thumbnail (`Metadata/thumbnail.png`), if present.
    public let packageThumbnail: Data?

    public init(unit: LengthUnit, plates: [BuildPlate], packageThumbnail: Data?) {
        self.unit = unit
        self.plates = plates
        self.packageThumbnail = packageThumbnail
    }

    /// Best thumbnail to use for a Finder icon / preview: the first plate's
    /// thumbnail if available, else the package thumbnail.
    public var primaryThumbnail: Data? {
        plates.first?.thumbnail ?? packageThumbnail
    }
}
