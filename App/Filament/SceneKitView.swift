import SwiftUI
import SceneKit
import ThreeMFKit

/// Wraps an `SCNView` configured for interactive orbit/pan/zoom of a build plate.
struct SceneKitView: NSViewRepresentable {
    let plate: BuildPlate
    var useModelColors: Bool = true
    var isDark: Bool = false
    /// Identity of the loaded document; changing it forces a scene rebuild even
    /// when the new document's plate shares an id with the old one.
    var documentToken: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(plateID: plate.id, useModelColors: useModelColors, isDark: isDark, documentToken: documentToken)
    }

    private var style: PreviewStyle {
        .studio(useModelColors: useModelColors, isDark: isDark)
    }

    func makeNSView(context: Context) -> SCNView {
        let view = ModelSCNView()
        view.display(scene: plate.makeScene(style: style))

        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.resetCamera))
        doubleClick.numberOfClicksRequired = 2
        view.addGestureRecognizer(doubleClick)
        context.coordinator.scnView = view

        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        // Only rebuild the scene when an input that affects it actually changes;
        // SwiftUI may call updateNSView for unrelated state updates.
        let plateChanged = context.coordinator.plateID != plate.id
        let documentChanged = context.coordinator.documentToken != documentToken
        let styleChanged = context.coordinator.useModelColors != useModelColors
            || context.coordinator.isDark != isDark
        guard plateChanged || documentChanged || styleChanged else { return }

        guard let view = nsView as? ModelSCNView else { return }

        context.coordinator.plateID = plate.id
        context.coordinator.documentToken = documentToken
        context.coordinator.useModelColors = useModelColors
        context.coordinator.isDark = isDark
        view.display(scene: plate.makeScene(style: style))
    }

    final class Coordinator {
        var plateID: Int
        var useModelColors: Bool
        var isDark: Bool
        var documentToken: Int
        weak var scnView: ModelSCNView?

        init(plateID: Int, useModelColors: Bool, isDark: Bool, documentToken: Int) {
            self.plateID = plateID
            self.useModelColors = useModelColors
            self.isDark = isDark
            self.documentToken = documentToken
        }

        /// Discards any orbit/pan/zoom the user applied by restoring the
        /// current camera to its initial framing.
        @objc func resetCamera() {
            scnView?.resetView()
        }
    }
}
