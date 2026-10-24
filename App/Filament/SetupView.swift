import SwiftUI
import AppKit
import Quartz

enum SetupWindow {
    static let id = "quicklook-setup"
    static let completedKey = "hasCompletedOnboarding"
}

/// Drives the in-app Quick Look panel used by the setup window's "Preview
/// Sample" step, so the user sees exactly what Finder's Space bar would show.
@MainActor
final class SamplePreviewController: NSObject, QLPreviewPanelDataSource {
    static let shared = SamplePreviewController()

    static var sampleURL: URL? {
        Bundle.main.url(forResource: "Filament Sample", withExtension: "3mf")
    }

    func showPreview() {
        guard Self.sampleURL != nil, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        Bundle.main.url(forResource: "Filament Sample", withExtension: "3mf") as NSURL?
    }
}

/// First-run / help window that walks through checking that Quick Look
/// previews and thumbnails work. Quick Look extension state can't be queried
/// from a sandboxed app, so this is a guided self-test instead.
struct SetupView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SetupWindow.completedKey) private var hasCompletedOnboarding = false

    private var isMacOS26OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section {
                    StepRow(
                        symbol: "eye",
                        title: "Try it",
                        detail: "Opens a sample model in Quick Look. You should see a colorful spool you can rotate. If you only see a file icon, turn on Filament’s extensions below.",
                        buttonTitle: "Preview Sample"
                    ) {
                        SamplePreviewController.shared.showPreview()
                    }
                    StepRow(
                        symbol: "gearshape",
                        title: "Turn on extensions",
                        detail: "In Extensions, choose Quick Look (or click ⓘ next to Filament) and make sure Filament’s previews and thumbnails are on.",
                        buttonTitle: "Open Quick Look Settings…"
                    ) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Section {
                    DisclosureGroup("Still not working?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Keep only one copy of Filament. Remove duplicates from Applications and ~/Applications.")
                            Text("• Open Filament once after updating so macOS registers the new extensions.")
                            if isMacOS26OrLater {
                                Text("• macOS 26 and later preview STL, OBJ, and PLY files with Apple’s built-in viewer by default. Filament always handles 3MF.")
                                if let url = URL(string: "https://github.com/akshaymaloo/filament#stlobjply-previews-on-macos-26") {
                                    Link("Use Filament for STL, OBJ, and PLY", destination: url)
                                }
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 520, height: 640)
        .onDisappear { hasCompletedOnboarding = true }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)
            Text("Welcome to Filament")
                .font(.system(size: 26, weight: .bold))
            Text("Preview 3MF, STL, OBJ, and PLY files in Finder with the Space bar. Here’s how to make sure it’s working.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
    }
}

private struct StepRow: View {
    let symbol: String
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(buttonTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
