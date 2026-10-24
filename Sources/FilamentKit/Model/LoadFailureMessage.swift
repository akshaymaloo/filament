import Foundation

/// Plain-English, user-facing copy for a failed (or empty) model load. Shared
/// by the Quick Look preview extension and the host app so both present the
/// same wording instead of leaking `FilamentError.description` internals.
public struct LoadFailureMessage: Equatable {
    /// What the user was trying to do when the load failed; only changes the
    /// wording ("Couldn't Preview…" vs "Couldn't Open…").
    public enum Context: Equatable {
        case preview
        case open

        fileprivate var verb: String {
            switch self {
            case .preview: return "preview"
            case .open: return "open"
            }
        }
    }

    public let title: String
    public let detail: String
    /// `true` when the file is only too big for the Quick Look preview budget,
    /// so opening it in the Filament app is expected to work.
    public let suggestsOpeningInApp: Bool

    /// Hint to show when no "Open in Filament" button can be offered.
    public static let openInAppHint = "Open it in Filament to view it."

    public init(title: String, detail: String, suggestsOpeningInApp: Bool = false) {
        self.title = title
        self.detail = detail
        self.suggestsOpeningInApp = suggestsOpeningInApp
    }

    public init(error: Error, fileName: String? = nil, context: Context = .preview) {
        let title = Self.title(fileName: fileName, context: context)
        let tooLarge = "This file is too large to \(context.verb)."
        switch error as? FilamentError {
        case .notAZipArchive, .corruptArchive, .unsupportedCompression:
            self.init(title: title, detail: "The file may be damaged, or it isn’t a valid 3MF file.")
        case .missingModelPart:
            self.init(title: title, detail: "The file doesn’t contain a 3D model.")
        case .malformedXML, .malformedMesh:
            self.init(title: title, detail: "The model data in this file couldn’t be read.")
        case .meshTooLarge(let triangles, _):
            self.init(
                title: title,
                detail: "This model is too large to \(context.verb) (\(PrintStatsFormatting.triangleCount(triangles))).",
                suggestsOpeningInApp: context == .preview
            )
        case .entryTooLarge, .archiveTooLarge:
            // The app enforces the same archive limits as the extension, so
            // opening it there wouldn't help.
            self.init(title: title, detail: tooLarge)
        case .cancelled:
            self.init(title: title, detail: "Loading was cancelled.")
        case nil:
            self.init(title: title, detail: "The file couldn’t be read.")
        }
    }

    /// A file that parsed but has no geometry.
    public static func emptyModel(fileName: String? = nil, context: Context = .preview) -> LoadFailureMessage {
        LoadFailureMessage(
            title: title(fileName: fileName, context: context),
            detail: "This file doesn’t contain any 3D geometry."
        )
    }

    /// A dropped file whose extension isn't one of the supported formats.
    public static func unsupportedFormat(fileName: String? = nil) -> LoadFailureMessage {
        LoadFailureMessage(
            title: title(fileName: fileName, context: .open),
            detail: "Filament opens 3MF, STL, OBJ, and PLY files."
        )
    }

    /// Whether `error` means the load was abandoned on purpose, in which case
    /// callers should not present a failure at all.
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case .cancelled? = error as? FilamentError { return true }
        return false
    }

    private static func title(fileName: String?, context: Context) -> String {
        let verb = context == .preview ? "Preview" : "Open"
        guard let fileName, !fileName.isEmpty else { return "Couldn’t \(verb) File" }
        return "Couldn’t \(verb) “\(fileName)”"
    }
}

extension ModelDocument {
    /// `true` when there is nothing to draw: every plate has zero triangles.
    public var hasNoGeometry: Bool {
        plates.allSatisfy { $0.mesh.triangleCount == 0 }
    }
}
