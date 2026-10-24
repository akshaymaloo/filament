import Cocoa
import Quartz
import SceneKit
import FilamentKit
import os.lock

/// A minimal thread-safe cancellation flag: `preparePreviewOfFile` parses
/// off the main actor via `Task.detached`, whose body doesn't observe the
/// parent task's cancellation directly, so `withTaskCancellationHandler`
/// flips this flag instead and the parser polls it via `shouldCancel`.
final class CancellationFlag: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        lock.withLock { $0 }
    }

    func cancel() {
        lock.withLock { $0 = true }
    }
}

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let scnView = ModelSCNView()

    // Top-right info overlay (dimensions, triangle count, slicer stats).
    private let overlayEffectView = NSVisualEffectView()
    private let overlayStack = NSStackView()

    // Bottom chrome: color toggle, file name, plate selector.
    private let bottomEffectView = NSVisualEffectView()
    private let bottomStack = NSStackView()
    private let colorModeControl = NSSegmentedControl()
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let plateControl = NSSegmentedControl()

    // Shown instead of the scene when the file can't be previewed.
    private let errorView = ErrorStateView()

    private var document: ModelDocument?
    private var url: URL?
    private var useModelColors = true
    private var currentPlateIndex = 0

    override func loadView() {
        let container = AppearanceObservingView()
        container.wantsLayer = true
        container.onAppearanceChange = { [weak self] in self?.appearanceChanged() }

        scnView.translatesAutoresizingMaskIntoConstraints = false
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(resetCamera))
        doubleClick.numberOfClicksRequired = 2
        scnView.addGestureRecognizer(doubleClick)
        container.addSubview(scnView)

        configureOverlay()
        container.addSubview(overlayEffectView)

        configureBottomBar()
        container.addSubview(bottomEffectView)

        errorView.translatesAutoresizingMaskIntoConstraints = false
        errorView.isHidden = true
        errorView.onOpenInApp = { [weak self] in self?.openInHostApp() }
        container.addSubview(errorView)

        NSLayoutConstraint.activate([
            errorView.topAnchor.constraint(equalTo: container.topAnchor),
            errorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            errorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            scnView.topAnchor.constraint(equalTo: container.topAnchor),
            scnView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scnView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scnView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            overlayEffectView.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            overlayEffectView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),

            overlayStack.topAnchor.constraint(equalTo: overlayEffectView.topAnchor),
            overlayStack.leadingAnchor.constraint(equalTo: overlayEffectView.leadingAnchor),
            overlayStack.trailingAnchor.constraint(equalTo: overlayEffectView.trailingAnchor),
            overlayStack.bottomAnchor.constraint(equalTo: overlayEffectView.bottomAnchor),

            bottomEffectView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            bottomEffectView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            bottomEffectView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 14),
            bottomEffectView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),

            bottomStack.topAnchor.constraint(equalTo: bottomEffectView.topAnchor, constant: 6),
            bottomStack.leadingAnchor.constraint(equalTo: bottomEffectView.leadingAnchor, constant: 10),
            bottomStack.trailingAnchor.constraint(equalTo: bottomEffectView.trailingAnchor, constant: -10),
            bottomStack.bottomAnchor.constraint(equalTo: bottomEffectView.bottomAnchor, constant: -6)
        ])

        view = container
    }

    private func configureOverlay() {
        overlayEffectView.translatesAutoresizingMaskIntoConstraints = false
        overlayEffectView.material = .hudWindow
        overlayEffectView.blendingMode = .withinWindow
        overlayEffectView.state = .active
        overlayEffectView.wantsLayer = true
        overlayEffectView.layer?.cornerRadius = 12
        overlayEffectView.layer?.masksToBounds = true

        overlayStack.orientation = .vertical
        overlayStack.alignment = .leading
        overlayStack.spacing = 4
        overlayStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        overlayStack.translatesAutoresizingMaskIntoConstraints = false
        overlayEffectView.addSubview(overlayStack)
    }

    private func configureBottomBar() {
        bottomEffectView.translatesAutoresizingMaskIntoConstraints = false
        bottomEffectView.material = .hudWindow
        bottomEffectView.blendingMode = .withinWindow
        bottomEffectView.state = .active
        bottomEffectView.wantsLayer = true
        bottomEffectView.layer?.cornerRadius = 12
        bottomEffectView.layer?.masksToBounds = true

        colorModeControl.translatesAutoresizingMaskIntoConstraints = false
        colorModeControl.segmentStyle = .texturedRounded
        colorModeControl.segmentCount = 2
        colorModeControl.setLabel("Color", forSegment: 0)
        colorModeControl.setLabel("Mono", forSegment: 1)
        colorModeControl.selectedSegment = 0
        colorModeControl.target = self
        colorModeControl.action = #selector(colorModeChanged)
        colorModeControl.isHidden = true
        colorModeControl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        fileNameLabel.font = .systemFont(ofSize: 11, weight: .regular)
        fileNameLabel.textColor = .secondaryLabelColor
        fileNameLabel.alignment = .center
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false

        plateControl.translatesAutoresizingMaskIntoConstraints = false
        plateControl.segmentStyle = .texturedRounded
        plateControl.target = self
        plateControl.action = #selector(plateSegmentChanged)
        plateControl.isHidden = true
        plateControl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        bottomStack.orientation = .horizontal
        bottomStack.alignment = .centerY
        bottomStack.spacing = 12
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.addArrangedSubview(colorModeControl)
        bottomStack.addArrangedSubview(fileNameLabel)
        bottomStack.addArrangedSubview(plateControl)
        bottomEffectView.addSubview(bottomStack)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Previews may involve very large meshes; users opted in by opening
        // Quick Look on this specific file, so the cap is generous (not
        // unlimited, to still bound worst-case memory/time) rather than the
        // stricter budget used for the ambient thumbnail extension.
        let flag = CancellationFlag()
        let fileName = url.lastPathComponent
        // QL may reuse this controller, so drop any previous state first.
        await MainActor.run { self.resetState() }

        let document: ModelDocument
        do {
            document = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    var options = ThreeMFLoader.Options.default
                    options.maxTriangles = 20_000_000
                    options.shouldCancel = { flag.isCancelled }
                    return try ModelLoader(options: options).load(url: url)
                }.value
            } onCancel: {
                flag.cancel()
            }
        } catch {
            if Task.isCancelled || LoadFailureMessage.isCancellation(error) {
                throw error
            }
            let message = LoadFailureMessage(error: error, fileName: fileName)
            await MainActor.run { self.showFailure(message, for: url) }
            return
        }

        await MainActor.run {
            guard !document.hasNoGeometry else {
                self.showFailure(.emptyModel(fileName: fileName), for: url)
                return
            }
            self.document = document
            self.url = url
            self.fileNameLabel.stringValue = fileName
            self.configurePlateSelector()
            self.displayPlate(at: self.plateControl.selectedSegment)
        }
    }

    /// Returns to the normal (non-error) layout and forgets the previous file.
    private func resetState() {
        document = nil
        url = nil
        errorView.isHidden = true
        scnView.isHidden = false
        bottomEffectView.isHidden = false
        overlayEffectView.isHidden = true
        colorModeControl.isHidden = true
        plateControl.isHidden = true
        useModelColors = true
        colorModeControl.selectedSegment = 0
        currentPlateIndex = 0
    }

    private func showFailure(_ message: LoadFailureMessage, for url: URL) {
        document = nil
        self.url = url
        scnView.isHidden = true
        overlayEffectView.isHidden = true
        bottomEffectView.isHidden = true
        errorView.configure(message, canOpenInApp: message.suggestsOpeningInApp && Self.hostAppURL != nil)
        errorView.isHidden = false
    }

    /// The containing `Filament.app` (`Filament.app/Contents/PlugIns/….appex`).
    private static var hostAppURL: URL? {
        var candidate = Bundle.main.bundleURL
        while candidate.pathComponents.count > 1 {
            candidate.deleteLastPathComponent()
            if candidate.pathExtension == "app" { return candidate }
        }
        return nil
    }

    private func openInHostApp() {
        guard let url, let appURL = Self.hostAppURL else {
            errorView.showOpenInAppFallback()
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard error != nil else { return }
            // The sandbox may refuse to launch the app; fall back to a text hint.
            DispatchQueue.main.async { self?.errorView.showOpenInAppFallback() }
        }
    }

    private func configurePlateSelector() {
        let plates = document?.plates ?? []
        plateControl.segmentCount = plates.count
        for (index, plate) in plates.enumerated() {
            plateControl.setLabel(plate.name, forSegment: index)
            plateControl.setWidth(0, forSegment: index)
        }
        plateControl.isHidden = plates.count <= 1
        if !plates.isEmpty {
            plateControl.selectedSegment = document?.defaultPlateIndex ?? 0
        }
    }

    @objc private func plateSegmentChanged() {
        displayPlate(at: plateControl.selectedSegment)
    }

    @objc private func colorModeChanged() {
        useModelColors = colorModeControl.selectedSegment == 0
        displayPlate(at: currentPlateIndex)
    }

    /// Resets the current camera to its initial framing, discarding any
    /// orbit/pan/zoom applied by the user.
    @objc private func resetCamera() {
        scnView.resetView()
    }

    /// Rebuilds the current plate when the host switches between light and dark
    /// appearance so the backdrop matches.
    private func appearanceChanged() {
        guard document != nil else { return }
        displayPlate(at: currentPlateIndex)
    }

    /// The studio style resolved for the current appearance and color mode.
    private func currentStyle() -> PreviewStyle {
        let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return .studio(useModelColors: useModelColors, isDark: isDark)
    }

    private func displayPlate(at index: Int) {
        guard let document, document.plates.indices.contains(index) else { return }
        currentPlateIndex = index
        let plate = document.plates[index]
        colorModeControl.isHidden = !plate.hasColorData
        scnView.display(scene: plate.makeScene(style: currentStyle()))
        updateOverlay(plate: plate, unit: document.unit)
    }

    private func updateOverlay(plate: BuildPlate, unit: LengthUnit) {
        overlayStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var rows: [String] = []
        if let dimensions = PrintStatsFormatting.dimensions(for: plate.mesh, unit: unit) {
            rows.append("▭ \(dimensions)")
        }
        rows.append("△ \(PrintStatsFormatting.triangleCount(plate.mesh.triangleCount))")

        if let stats = plate.stats {
            if let seconds = stats.predictionSeconds {
                rows.append("⏱ \(PrintStatsFormatting.duration(seconds: seconds))")
            }
            if let grams = stats.weightGrams {
                rows.append("⚖︎ \(PrintStatsFormatting.weight(grams: grams))")
            }
            if let printer = stats.printerModel {
                rows.append("🖨 \(printer)")
            }
        }

        overlayEffectView.isHidden = rows.isEmpty
        for row in rows {
            let label = NSTextField(labelWithString: row)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            overlayStack.addArrangedSubview(label)
        }
    }
}

/// A container `NSView` that invokes a callback whenever its effective
/// appearance changes (light ⇄ dark), so the controller can rebuild the scene
/// with a matching backdrop.
private final class AppearanceObservingView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// Native-looking "can't preview" state: a symbol, a title, a short
/// explanation and, when useful, an "Open in Filament" button.
private final class ErrorStateView: NSView {
    var onOpenInApp: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open in Filament", target: nil, action: nil)
    private let hintLabel = NSTextField(wrappingLabelWithString: LoadFailureMessage.openInAppHint)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        let configuration = NSImage.SymbolConfiguration(pointSize: 44, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: .tertiaryLabelColor))
        iconView.image = symbol?.withSymbolConfiguration(configuration)
        iconView.setAccessibilityElement(false)

        configure(titleLabel, font: .systemFont(ofSize: 17, weight: .semibold), color: .labelColor, maxLines: 3)
        configure(detailLabel, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, maxLines: 0)
        configure(hintLabel, font: .systemFont(ofSize: 13), color: .secondaryLabelColor, maxLines: 0)

        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openTapped)

        let stack = NSStackView(views: [iconView, titleLabel, detailLabel, openButton, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.setCustomSpacing(12, after: iconView)
        stack.setCustomSpacing(16, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            hintLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configure(_ label: NSTextField, font: NSFont, color: NSColor, maxLines: Int) {
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.maximumNumberOfLines = maxLines
        label.preferredMaxLayoutWidth = 360
        label.isSelectable = false
    }

    func configure(_ message: LoadFailureMessage, canOpenInApp: Bool) {
        titleLabel.stringValue = message.title
        detailLabel.stringValue = message.detail
        openButton.isHidden = !canOpenInApp
        // Without a button, still tell the user how to view an oversized model.
        hintLabel.isHidden = canOpenInApp || !message.suggestsOpeningInApp
    }

    func showOpenInAppFallback() {
        openButton.isHidden = true
        hintLabel.isHidden = false
    }

    @objc private func openTapped() {
        onOpenInApp?()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
}
