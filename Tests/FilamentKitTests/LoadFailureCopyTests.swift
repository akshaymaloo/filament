import XCTest
@testable import FilamentKit

/// Lints all user-facing error copy. `samples(for:)` switches exhaustively
/// over `FilamentError`, so adding a case without updating this file (and
/// therefore the copy) fails to compile.
final class LoadFailureCopyTests: XCTestCase {
    private func samples(for error: FilamentError) -> [FilamentError] {
        switch error {
        case .notAZipArchive: return [.notAZipArchive]
        case .missingModelPart: return [.missingModelPart]
        case .malformedXML: return [.malformedXML("x")]
        case .entryTooLarge: return [.entryTooLarge(path: "a", size: 2, limit: 1)]
        case .unsupportedCompression: return [.unsupportedCompression(method: 99)]
        case .corruptArchive: return [.corruptArchive("x")]
        case .malformedMesh: return [.malformedMesh("x")]
        case .meshTooLarge: return [.meshTooLarge(triangles: 10, limit: 1)]
        case .cancelled: return [.cancelled]
        case .archiveTooLarge: return [.archiveTooLarge(limit: 1)]
        }
    }

    private var allErrors: [FilamentError] {
        let seeds: [FilamentError] = [
            .notAZipArchive, .missingModelPart, .malformedXML(""), .entryTooLarge(path: "", size: 0, limit: 0),
            .unsupportedCompression(method: 0), .corruptArchive(""), .malformedMesh(""),
            .meshTooLarge(triangles: 0, limit: 0), .cancelled, .archiveTooLarge(limit: 0),
        ]
        return seeds.flatMap(samples(for:))
    }

    private let contexts: [LoadFailureMessage.Context] = [.preview, .open]
    private let names: [String?] = [nil, "Spool.3mf"]

    private func allMessages() -> [(String, LoadFailureMessage, String?)] {
        var out: [(String, LoadFailureMessage, String?)] = []
        for context in contexts {
            for name in names {
                for error in allErrors {
                    out.append(("\(error) \(context)", LoadFailureMessage(error: error, fileName: name, context: context), name))
                }
                out.append(("unknown \(context)", LoadFailureMessage(error: CocoaError(.fileReadUnknown), fileName: name, context: context), name))
                out.append(("cancellation \(context)", LoadFailureMessage(error: CancellationError(), fileName: name, context: context), name))
                out.append(("empty \(context)", .emptyModel(fileName: name, context: context), name))
            }
        }
        for name in names {
            out.append(("unsupported", .unsupportedFormat(fileName: name), name))
        }
        return out
    }

    func testEveryMessageHasWellFormedCopy() {
        for (label, message, name) in allMessages() {
            XCTAssertFalse(message.title.isEmpty, label)
            XCTAssertFalse(message.detail.isEmpty, label)
            if let name {
                XCTAssertTrue(message.title.contains("“\(name)”"), "\(label): \(message.title)")
            }
            for text in [message.title, message.detail, LoadFailureMessage.openInAppHint] {
                XCTAssertFalse(text.contains("'"), "\(label): straight apostrophe in \(text)")
                XCTAssertFalse(text.replacingOccurrences(of: name ?? "\u{0}", with: "").contains("\""), "\(label): straight quote in \(text)")
            }
            XCTAssertTrue(message.detail.hasSuffix("."), "\(label): \(message.detail)")
        }
    }

    func testContextChangesTitleVerb() {
        XCTAssertEqual(LoadFailureMessage.emptyModel(context: .preview).title, "Couldn’t Preview File")
        XCTAssertEqual(LoadFailureMessage.emptyModel(context: .open).title, "Couldn’t Open File")
    }

    func testCancellationDetection() {
        XCTAssertTrue(LoadFailureMessage.isCancellation(CancellationError()))
        XCTAssertTrue(LoadFailureMessage.isCancellation(FilamentError.cancelled))
        XCTAssertFalse(LoadFailureMessage.isCancellation(FilamentError.missingModelPart))
    }
}
