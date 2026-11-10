import SwiftUI
import AppKit

/// A slicer Filament can hand the open file to ("Open in Bambu Studio").
struct Slicer: Identifiable {
    let bundleIdentifier: String
    let name: String
    /// Menu shortcut that opens the current file in this slicer.
    let shortcut: KeyboardShortcut
    /// The same shortcut as shown in the button tooltip.
    let shortcutLabel: String

    var id: String { bundleIdentifier }

    /// Slicers offered in the toolbar and the File menu, in display order.
    /// Only the ones installed on this Mac are shown.
    /// Bambu Studio opens with ⌘↩, QIDI Studio with a plain ↩.
    static let known: [Slicer] = [
        Slicer(bundleIdentifier: "com.bambulab.bambu-studio", name: "Bambu Studio",
               shortcut: KeyboardShortcut(.return, modifiers: .command), shortcutLabel: "⌘↩"),
        Slicer(bundleIdentifier: "com.qiditech.qidi-studio", name: "QIDI Studio",
               shortcut: KeyboardShortcut(.return, modifiers: []), shortcutLabel: "↩"),
    ]

    /// Installed slicers, resolved through Launch Services.
    static var installed: [Slicer] {
        known.filter { $0.applicationURL != nil }
    }

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    /// The slicer's own app icon, so the button is recognisable at a glance.
    var icon: NSImage? {
        guard let url = applicationURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Opens `fileURL` in this slicer and brings it to the front.
    func open(_ fileURL: URL) {
        guard let appURL = applicationURL else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Couldn't open in \(name)"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

/// Toolbar buttons (top-right of the window) that open the current file in
/// an installed slicer: app icon + name.
struct OpenInSlicerToolbar: ToolbarContent {
    let fileURL: URL?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let fileURL {
                ForEach(Slicer.installed) { slicer in
                    Button {
                        slicer.open(fileURL)
                    } label: {
                        SlicerButtonLabel(slicer: slicer)
                    }
                    .help("Open in \(slicer.name) (\(slicer.shortcutLabel))")
                    .accessibilityLabel("Open in \(slicer.name)")
                }
            }
        }
    }
}

private struct SlicerButtonLabel: View {
    let slicer: Slicer

    var body: some View {
        HStack(spacing: 5) {
            if let icon = slicer.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }
            Text(slicer.name)
        }
        .padding(.horizontal, 2)
    }
}
