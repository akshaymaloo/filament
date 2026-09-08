import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Known third-party 3MF UTIs. Other apps (Shapr3D, Bambu Studio, etc.) register
/// their own identifier for `.3mf`; Quick Look and the Open panel key off the
/// file's resolved UTI, so we claim these in addition to `com.filament3d.3mf`.
let additionalThreeMFTypeIdentifiers = [
    "com.shapr3d.3d-manufacturing.3mf",
    "com.microsoft.package.3dmanufacturing",
    "org.3mf.threemfpackage",
    "org.3mf.threemfformat",
    "org.3mf.model",
    "org.3mf.3mf",
    "com.bambulab.3mf",
]

/// The UTIs for the four model formats Filament can open: 3MF (custom, declared in
/// Info.plist) plus the system-declared STL/OBJ/PLY identifiers, used to filter the
/// open panel and drag-and-drop. Also includes whichever UTI Launch Services
/// currently prefers for the `.3mf` extension, so files claimed by another app
/// still appear in the Open panel.
let supportedTypes: [UTType] = {
    var types: [UTType] = [
        "com.filament3d.3mf",
        "public.standard-tesselated-geometry-format",
        "public.geometry-definition-format",
        "public.polygon-file-format",
    ].compactMap { UTType($0) }
    if let extType = UTType(filenameExtension: "3mf"), !types.contains(extType) {
        types.insert(extType, at: 0)
    }
    for id in additionalThreeMFTypeIdentifiers {
        if let type = UTType(id), !types.contains(type) {
            types.append(type)
        }
    }
    return types
}()

@main
struct FilamentApp: App {
    @StateObject private var model = DocumentModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 520)
                // Load files opened from Finder (double-click / "Open With"),
                // since Filament is a registered viewer for these types.
                .onOpenURL { url in
                    model.load(url: url)
                }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Reload") {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.fileURL == nil)

                Button("Reveal in Finder") {
                    revealInFinder()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.fileURL == nil)

                Button("Close File") {
                    model.reset()
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(model.document == nil && model.errorMessage == nil)
            }
        }
    }

    /// Presents an `NSOpenPanel` filtered to supported model files and loads the chosen document.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.load(url: url)
        }
    }

    /// Reveals the currently open file in Finder.
    private func revealInFinder() {
        guard let url = model.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
