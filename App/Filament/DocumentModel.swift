import Foundation
import ThreeMFKit
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
    @Published private(set) var document: ThreeMFDocument?
    @Published var selectedPlateIndex: Int = 0
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var fileURL: URL?
    /// Increments on every successful load. Used as a stable identity so the
    /// SceneKit view rebuilds even when two different documents share the same
    /// plate id (implicit single plates are always id 1).
    @Published private(set) var loadGeneration = 0

    /// Cancellation flag for whichever load is currently in flight, so a new
    /// `load(url:)` call can abandon a superseded one instead of racing it.
    private var currentLoadCancellationFlag: LoadCancellationFlag?

    /// Loads a 3MF/STL/OBJ/PLY file asynchronously and publishes the result.
    func load(url: URL) {
        currentLoadCancellationFlag?.cancel()
        let flag = LoadCancellationFlag()
        currentLoadCancellationFlag = flag

        isLoading = true
        errorMessage = nil
        Task {
            do {
                var options = ThreeMFLoader.Options.default
                options.shouldCancel = { flag.isCancelled }
                let loader = ModelLoader(options: options)
                let doc = try await Task.detached(priority: .userInitiated) {
                    try loader.load(url: url)
                }.value
                guard !flag.isCancelled else { return }
                self.document = doc
                self.selectedPlateIndex = 0
                self.fileURL = url
                self.loadGeneration += 1
                self.isLoading = false
            } catch {
                guard !flag.isCancelled else { return }
                self.errorMessage = Self.describe(error)
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
        errorMessage = nil
        fileURL = nil
    }

    /// Sets a friendly error for dropped files whose extension isn't a supported model format.
    func setUnsupportedFormatError() {
        errorMessage = "Unsupported file type. Filament opens 3MF, STL, OBJ, and PLY files."
    }

    private static func describe(_ error: Error) -> String {
        if let threeMFError = error as? ThreeMFError {
            return threeMFError.description
        }
        return error.localizedDescription
    }
}
