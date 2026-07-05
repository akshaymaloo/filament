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
    /// Per-camera-node reset state (keyed by node name, e.g. "camera3D"),
    /// captured right after a scene is loaded so `resetView()` can undo any
    /// orbit/pan/zoom the user applied.
    private var initialStates: [String: (transform: SCNMatrix4, fov: CGFloat, ortho: Double)] = [:]

    /// Sets the scene, configures interactive controls, captures reset state,
    /// and applies the given camera mode.
    public func display(scene newScene: SCNScene, mode: PreviewCameraMode) {
        scene = newScene
        allowsCameraControl = true
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        rendersContinuously = false

        initialStates.removeAll()
        for cameraMode in [PreviewCameraMode.threeD, .twoD] {
            guard let node = newScene.previewCameraNode(for: cameraMode), let camera = node.camera else { continue }
            let name = node.name ?? ""
            initialStates[name] = (transform: node.transform, fov: camera.fieldOfView, ortho: camera.orthographicScale)
        }

        apply(mode: mode)
    }

    /// Switches between the perspective ("3D") and orthographic front ("2D")
    /// cameras and the matching interaction mode.
    public func apply(mode: PreviewCameraMode) {
        guard let node = scene?.previewCameraNode(for: mode) else { return }
        pointOfView = node
        defaultCameraController.interactionMode = (mode == .threeD) ? .orbitTurntable : .pan
    }

    /// Restores the current camera to its initial framing (undo orbit/pan/zoom).
    public func resetView() {
        guard let node = pointOfView, let camera = node.camera, let initial = initialStates[node.name ?? ""] else { return }
        node.transform = initial.transform
        camera.fieldOfView = initial.fov
        camera.orthographicScale = initial.ortho
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
    /// the current camera. Perspective cameras zoom via `fieldOfView` (smaller
    /// is more zoomed in); orthographic cameras zoom via `orthographicScale`,
    /// clamped to +/-10x of their initial scale to keep the front view usable.
    private func zoom(factor: CGFloat) {
        guard factor > 0, let node = pointOfView, let cam = node.camera else { return }
        if cam.usesOrthographicProjection {
            let base = initialStates[node.name ?? ""]?.ortho ?? cam.orthographicScale
            let proposed = cam.orthographicScale * Double(factor)
            cam.orthographicScale = min(max(proposed, base * 0.1), base * 10)
        } else {
            cam.fieldOfView = min(max(cam.fieldOfView * factor, 3), 90)
        }
    }
}
#endif
