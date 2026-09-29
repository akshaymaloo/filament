import Cocoa
import Quartz
import SceneKit
import ThreeMFKit
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

    private var document: ThreeMFDocument?
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

        NSLayoutConstraint.activate([
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
        let document = try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                var options = ThreeMFLoader.Options.default
                options.maxTriangles = 20_000_000
                options.shouldCancel = { flag.isCancelled }
                return try ModelLoader(options: options).load(url: url)
            }.value
        } onCancel: {
            flag.cancel()
        }

        await MainActor.run {
            self.document = document
            self.url = url
            self.fileNameLabel.stringValue = url.lastPathComponent
            self.configurePlateSelector()
            self.displayPlate(at: 0)
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
            plateControl.selectedSegment = 0
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
