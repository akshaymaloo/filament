#if canImport(SceneKit)
import SceneKit
#if canImport(AppKit)
import AppKit
#endif

/// Visual styling knobs for `BuildPlate.makeScene(style:)`.
public struct PreviewStyle {
    public var modelColor: NSColor
    public var backgroundColor: NSColor
    /// A ground plane at the model's base that receives a soft contact shadow.
    public var showGroundPlane: Bool
    /// A soft, shadow-casting key light (plus fill/rim lights) for studio-style depth.
    public var enableShadows: Bool
    /// Image-based lighting (a soft studio environment) so PBR materials pick up gentle reflections.
    public var enableEnvironmentLighting: Bool

    public init(
        modelColor: NSColor,
        backgroundColor: NSColor,
        showGroundPlane: Bool,
        enableShadows: Bool,
        enableEnvironmentLighting: Bool
    ) {
        self.modelColor = modelColor
        self.backgroundColor = backgroundColor
        self.showGroundPlane = showGroundPlane
        self.enableShadows = enableShadows
        self.enableEnvironmentLighting = enableEnvironmentLighting
    }

    /// A pleasant, Apple-like neutral studio look: light-gray model on a subtle
    /// near-white backdrop, with a soft contact shadow and gentle reflections.
    public static var `default`: PreviewStyle {
        PreviewStyle(
            modelColor: NSColor(calibratedWhite: 0.82, alpha: 1.0),
            backgroundColor: NSColor(calibratedWhite: 0.93, alpha: 1.0),
            showGroundPlane: true,
            enableShadows: true,
            enableEnvironmentLighting: true
        )
    }
}
#endif
