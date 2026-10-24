import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers
import FilamentKit

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

    @State private var defaultsStatus = DefaultAppStatus.current()
    @State private var defaultsError: String?
    @State private var copied = false

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
                    DefaultAppRow(status: defaultsStatus, error: defaultsError) { makeDefault() }
                    if #available(macOS 26, *) {
                        StepRow(
                            symbol: "terminal",
                            title: "Use Filament for STL, OBJ, and PLY previews",
                            detail: "macOS’s built-in viewer previews these formats first. To use Filament instead, copy the command, paste it into Terminal, and press Return. (Sandboxed apps can’t change this setting themselves.)",
                            buttonTitle: copied ? "Copied" : "Copy Command",
                            secondaryTitle: "Open Terminal",
                            action: copyCommand,
                            secondaryAction: openTerminal
                        )
                    }
                }
                Section {
                    DisclosureGroup("Still not working?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Keep only one copy of Filament. Remove duplicates from Applications and ~/Applications.")
                            Text("• Open Filament once after updating so macOS registers the new extensions.")
                            if #available(macOS 26, *) {
                                Text("• To go back to Apple’s viewer for STL, OBJ, and PLY, run this in Terminal:")
                                Text(QuickLookSetup.restoreAppleCommand)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                if let url = URL(string: "https://github.com/akshaymaloo/filament#stlobjply-previews-on-macos-26") {
                                    Link("Read more about STL, OBJ, and PLY previews", destination: url)
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
        .frame(width: 520, height: 720)
        .onDisappear { hasCompletedOnboarding = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            defaultsStatus = .current()
        }
    }

    private func makeDefault() {
        defaultsError = nil
        let appURL = Bundle.main.bundleURL
        let ownID = Bundle.main.bundleIdentifier ?? ""
        let pending = QuickLookSetup.extensionsNeedingChange(defaults: defaultsStatus.defaults, ownBundleID: ownID)
        let group = DispatchGroup()
        var failures: [String] = []
        for ext in pending {
            guard let type = DefaultAppStatus.type(for: ext) else { continue }
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                DispatchQueue.main.async {
                    if let error { failures.append(error.localizedDescription) }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            defaultsStatus = .current()
            if let first = failures.first {
                defaultsError = "Couldn’t change the default app: \(first)"
            }
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(QuickLookSetup.preferFilamentCommand, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
    }

    private func openTerminal() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
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
    var secondaryTitle: String?
    let action: () -> Void
    var secondaryAction: (() -> Void)?

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
                HStack {
                    Button(buttonTitle, action: action)
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Current default app (by bundle ID and display name) for each file type.
struct DefaultAppStatus {
    var defaults: [String: String?]
    var names: [String: String]

    static func type(for ext: String) -> UTType? {
        ext == "3mf" ? (UTType("com.filament3d.3mf") ?? UTType(filenameExtension: ext)) : UTType(filenameExtension: ext)
    }

    static func current() -> DefaultAppStatus {
        var defaults: [String: String?] = [:]
        var names: [String: String] = [:]
        for ext in QuickLookSetup.supportedExtensions {
            guard let type = type(for: ext),
                  let url = NSWorkspace.shared.urlForApplication(toOpen: type),
                  let id = Bundle(url: url)?.bundleIdentifier else {
                defaults[ext] = .some(nil)
                continue
            }
            defaults[ext] = .some(id)
            names[id] = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return DefaultAppStatus(defaults: defaults, names: names)
    }

    var ownID: String { Bundle.main.bundleIdentifier ?? "" }

    var isAllFilament: Bool {
        QuickLookSetup.extensionsNeedingChange(defaults: defaults, ownBundleID: ownID).isEmpty
    }

    var text: String {
        QuickLookSetup.statusText(defaults: defaults, ownBundleID: ownID, appNames: names)
    }
}

private struct DefaultAppRow: View {
    let status: DefaultAppStatus
    let error: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Open 3D files with Filament").font(.headline)
                if status.isAllFilament {
                    Label(status.text, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                } else {
                    Text(status.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Make Filament the Default App", action: action)
                        .padding(.top, 4)
                }
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
