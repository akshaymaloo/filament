import Foundation
import FilamentKit
import os.lock

/// Thread-safe flag threaded into `ThreeMFLoader.Options.shouldCancel` so an
/// in-flight background load can be abandoned when a new file replaces it.
private final class LoadCancellationFlag: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var isCancelled: Bool { lock.withLock { $0 } }
    func cancel() { lock.withLock { $0 = true } }
}

/// Observable app-wide state: the currently loaded document, the selected
/// plate, and any load error. Loading happens off the main thread.
@MainActor
final class DocumentModel: ObservableObject {
    @Published private(set) var document: ModelDocument?
    @Published var selectedPlateIndex: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var failure: LoadFailureMessage?
    @Published private(set) var fileURL: URL?
    /// Increments on every successful load. Used as a stable identity so the
    /// SceneKit view rebuilds even when two different documents share the same
    /// plate id (implicit single plates are always id 1).
    @Published private(set) var loadGeneration = 0

    /// Set when the app was asked to open a file (Finder double-click, "Open
    /// With"), which defers the first-run setup window.
    private(set) var didReceiveOpenRequest = false

    /// Cancellation flag for whichever load is currently in flight, so a new
    /// `load(url:)` call can abandon a superseded one instead of racing it.
    private var currentLoadCancellationFlag: LoadCancellationFlag?

    /// Loads a file the system asked the app to open.
    func open(url: URL) {
        didReceiveOpenRequest = true
        load(url: url)
    }

    /// Loads a 3MF/STL/OBJ/PLY file asynchronously and publishes the result.
    func load(url: URL) {
        currentLoadCancellationFlag?.cancel()
        let flag = LoadCancellationFlag()
        currentLoadCancellationFlag = flag

        isLoading = true
        failure = nil
        Task {
            do {
                var options = ThreeMFLoader.Options.default
                options.shouldCancel = { flag.isCancelled }
                let loader = ModelLoader(options: options)
                let doc = try await Task.detached(priority: .userInitiated) {
                    try loader.load(url: url)
                }.value
                guard !flag.isCancelled else { return }
                if doc.hasNoGeometry {
                    self.document = nil
                    self.fileURL = url
                    self.failure = .emptyModel(fileName: url.lastPathComponent, context: .open)
                    self.isLoading = false
                    return
                }
                self.document = doc
                self.selectedPlateIndex = doc.defaultPlateIndex
                self.fileURL = url
                self.loadGeneration += 1
                self.isLoading = false
            } catch {
                guard !flag.isCancelled, !LoadFailureMessage.isCancellation(error) else { return }
                self.document = nil
                self.fileURL = url
                self.failure = LoadFailureMessage(error: error, fileName: url.lastPathComponent, context: .open)
                self.isLoading = false
            }
        }
    }

    /// Reloads the currently open file from disk, if any.
    func reload() {
        guard let url = fileURL else { return }
        load(url: url)
    }

    func reset() {
        document = nil
        selectedPlateIndex = 0
        failure = nil
        fileURL = nil
    }

    /// Shows the unsupported-format message for a dropped file.
    func setUnsupportedFormatError(fileName: String) {
        currentLoadCancellationFlag?.cancel()
        isLoading = false
        document = nil
        fileURL = nil
        failure = .unsupportedFormat(fileName: fileName)
    }
}
