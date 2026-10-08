#if canImport(SceneKit) && canImport(AppKit)
import SceneKit
import AppKit

/// An `SCNView` subclass shared by the app and the Quick Look preview
/// extension so both hosts drive the camera identically. Orbit/pan is left
/// to SceneKit's built-in `allowsCameraControl` (drag gestures work fine in
/// both hosts), but zoom is handled explicitly: in the remote-hosted preview
/// extension, `SCNView`'s own scroll/pinch zoom handling is unreliable, so
/// `scrollWheel`/`magnify` are overridden here to adjust the camera directly.
public final class ModelSCNView: SCNView {
    /// The camera's initial state, captured right after a scene is loaded so
    /// `resetView()` can undo any orbit/pan/zoom the user applied.
    private var initialTransform: SCNMatrix4?
    private var initialFOV: CGFloat = 30

    /// Sets the scene, configures interactive orbit controls, and captures the
    /// reset state.
    public func display(scene newScene: SCNScene) {
        scene = newScene
        allowsCameraControl = true
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        rendersContinuously = false
        defaultCameraController.interactionMode = .orbitTurntable

        if let node = newScene.previewCameraNode {
            pointOfView = node
            initialTransform = node.transform
            initialFOV = node.camera?.fieldOfView ?? 30
        }
    }

    /// Restores the camera to its initial framing (undo orbit/pan/zoom).
    public func resetView() {
        guard let node = pointOfView, let camera = node.camera, let transform = initialTransform else { return }
        node.transform = transform
        camera.fieldOfView = initialFOV
    }

    /// Explicit scroll-wheel zoom. Overridden (without calling `super`) because
    /// `allowsCameraControl`'s own scroll handling is unreliable when this view
    /// is remote-hosted (as it is inside the Quick Look preview extension).
    public override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        zoom(factor: exp(-delta * 0.01))
    }

    /// Explicit pinch (magnify) zoom. Convention: pinch-out (positive
    /// magnification) zooms in, matching Trackpad/Photos/Maps behavior.
    public override func magnify(with event: NSEvent) {
        zoom(factor: 1 - event.magnification)
    }

    /// Applies a multiplicative zoom `factor` (< 1 zooms in, > 1 zooms out) to
    /// the perspective camera via `fieldOfView` (smaller is more zoomed in).
    private func zoom(factor: CGFloat) {
        guard factor > 0, let node = pointOfView, let cam = node.camera else { return }
        cam.fieldOfView = min(max(cam.fieldOfView * factor, 3), 90)
    }
}
#endif
