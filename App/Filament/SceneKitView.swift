import SwiftUI
import SceneKit
import ThreeMFKit

/// Wraps an `SCNView` configured for interactive orbit/pan/zoom of a build plate.
struct SceneKitView: NSViewRepresentable {
    let plate: BuildPlate
    var cameraMode: PreviewCameraMode = .threeD
    var useModelColors: Bool = true
    var isDark: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(plateID: plate.id, cameraMode: cameraMode, useModelColors: useModelColors, isDark: isDark)
    }

    private var style: PreviewStyle {
        .studio(useModelColors: useModelColors, isDark: isDark)
    }

    func makeNSView(context: Context) -> SCNView {
        let view = ModelSCNView()
        view.display(scene: plate.makeScene(style: style), mode: cameraMode)

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
        let modeChanged = context.coordinator.cameraMode != cameraMode
        let styleChanged = context.coordinator.useModelColors != useModelColors
            || context.coordinator.isDark != isDark
        guard plateChanged || modeChanged || styleChanged else { return }

        guard let view = nsView as? ModelSCNView else { return }

        if plateChanged || styleChanged {
            context.coordinator.plateID = plate.id
            context.coordinator.useModelColors = useModelColors
            context.coordinator.isDark = isDark
            view.display(scene: plate.makeScene(style: style), mode: cameraMode)
        } else if modeChanged {
            // Switching between the perspective ("3D") and orthographic front
            // ("2D") cameras also switches the appropriate camera-control
            // gesture: orbiting makes no sense for a front elevation view, so
            // 2D uses pan (drag to move, scroll/pinch to zoom) instead.
            view.apply(mode: cameraMode)
        }
        context.coordinator.cameraMode = cameraMode
    }

    final class Coordinator {
        var plateID: Int
        var cameraMode: PreviewCameraMode
        var useModelColors: Bool
        var isDark: Bool
        weak var scnView: ModelSCNView?

        init(plateID: Int, cameraMode: PreviewCameraMode, useModelColors: Bool, isDark: Bool) {
            self.plateID = plateID
            self.cameraMode = cameraMode
            self.useModelColors = useModelColors
            self.isDark = isDark
        }

        /// Discards any orbit/pan/zoom the user applied by restoring the
        /// current camera to its initial framing.
        @objc func resetCamera() {
            scnView?.resetView()
        }
    }
}
