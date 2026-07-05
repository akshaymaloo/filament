import Cocoa
import Quartz
import SceneKit
import ThreeMFKit

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let scnView = ModelSCNView()

    // Top-right info overlay (dimensions, triangle count, slicer stats).
    private let overlayEffectView = NSVisualEffectView()
    private let overlayStack = NSStackView()

    // Bottom chrome: 2D/3D toggle, file name, plate selector — all in one bar.
    private let bottomEffectView = NSVisualEffectView()
    private let bottomStack = NSStackView()
    private let cameraModeControl = NSSegmentedControl()
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let plateControl = NSSegmentedControl()

    private var document: ThreeMFDocument?
    private var url: URL?
    private var cameraMode: PreviewCameraMode = .threeD

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

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

        cameraModeControl.translatesAutoresizingMaskIntoConstraints = false
        cameraModeControl.segmentStyle = .texturedRounded
        cameraModeControl.segmentCount = 2
        cameraModeControl.setLabel("2D", forSegment: 0)
        cameraModeControl.setLabel("3D", forSegment: 1)
        cameraModeControl.selectedSegment = 1
        cameraModeControl.target = self
        cameraModeControl.action = #selector(cameraModeChanged)
        cameraModeControl.setContentHuggingPriority(.defaultHigh, for: .horizontal)

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
        bottomStack.addArrangedSubview(cameraModeControl)
        bottomStack.addArrangedSubview(fileNameLabel)
        bottomStack.addArrangedSubview(plateControl)
        bottomEffectView.addSubview(bottomStack)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let document = try ModelLoader().load(url: url)

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

    @objc private func cameraModeChanged() {
        cameraMode = cameraModeControl.selectedSegment == 0 ? .twoD : .threeD
        scnView.apply(mode: cameraMode)
    }

    /// Resets the current camera to its initial framing, discarding any
    /// orbit/pan/zoom applied by the user.
    @objc private func resetCamera() {
        scnView.resetView()
    }

    private func displayPlate(at index: Int) {
        guard let document, document.plates.indices.contains(index) else { return }
        let plate = document.plates[index]
        scnView.display(scene: plate.makeScene(), mode: cameraMode)
        updateOverlay(plate: plate, unit: document.unit)
    }

    private func updateOverlay(plate: BuildPlate, unit: LengthUnit) {
        overlayStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        var rows: [String] = []
        if let dimensions = PreviewFormatter.dimensions(for: plate.mesh, unit: unit) {
            rows.append("▭ \(dimensions)")
        }
        rows.append("△ \(PreviewFormatter.triangleCount(plate.mesh.triangleCount))")

        if let stats = plate.stats {
            if let seconds = stats.predictionSeconds {
                rows.append("⏱ \(PreviewFormatter.duration(seconds: seconds))")
            }
            if let grams = stats.weightGrams {
                rows.append("⚖︎ \(PreviewFormatter.weight(grams: grams))")
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

/// Small formatting helpers for the preview extension's overlay.
private enum PreviewFormatter {
    static func duration(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func weight(grams: Double) -> String {
        String(format: "%.1f g", grams)
    }

    /// Formats a mesh's bounding box as "W × D × H mm", converting from the
    /// document's declared length unit into millimeters. Returns `nil` for an
    /// empty mesh (no bounding box).
    static func dimensions(for mesh: TriangleMesh, unit: LengthUnit) -> String? {
        guard let box = mesh.boundingBox else { return nil }
        let mmPerUnit = Float(unit.millimetersPerUnit)
        let size = box.max - box.min
        let width = size.x * mmPerUnit
        let depth = size.y * mmPerUnit
        let height = size.z * mmPerUnit
        return String(format: "%.1f × %.1f × %.1f mm", width, depth, height)
    }

    /// Formats a triangle count with thousands separators, e.g. "12,345 triangles".
    static func triangleCount(_ count: Int) -> String {
        let formatted = Formatter.groupedInteger.string(from: NSNumber(value: count)) ?? "\(count)"
        return count == 1 ? "\(formatted) triangle" : "\(formatted) triangles"
    }
}

private extension Formatter {
    static let groupedInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}
