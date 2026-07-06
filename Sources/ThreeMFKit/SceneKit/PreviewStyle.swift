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
    /// When `true` (the default), a plate with a non-empty `palette` and
    /// per-triangle color data renders each filament in its real slicer
    /// color (one `SCNGeometry`/material per distinct color). When `false`,
    /// or when the plate has no color data, the model renders as a single
    /// neutral `modelColor` material, as before.
    public var useModelColors: Bool

    public init(
        modelColor: NSColor,
        backgroundColor: NSColor,
        showGroundPlane: Bool,
        enableShadows: Bool,
        enableEnvironmentLighting: Bool,
        useModelColors: Bool = true
    ) {
        self.modelColor = modelColor
        self.backgroundColor = backgroundColor
        self.showGroundPlane = showGroundPlane
        self.enableShadows = enableShadows
        self.enableEnvironmentLighting = enableEnvironmentLighting
        self.useModelColors = useModelColors
    }

    /// A pleasant, Apple-like neutral studio look: light-gray model on a subtle
    /// near-white backdrop, with a soft contact shadow and gentle reflections.
    public static var `default`: PreviewStyle {
        studio(useModelColors: true, isDark: false)
    }

    /// The studio look, resolved for the host's appearance and color mode.
    /// - Parameters:
    ///   - useModelColors: render real filament colors (when the plate has a
    ///     palette) versus a single neutral material.
    ///   - isDark: use a dark backdrop/contact plane so the preview matches a
    ///     dark-mode host; otherwise the light near-white backdrop.
    public static func studio(useModelColors: Bool, isDark: Bool) -> PreviewStyle {
        PreviewStyle(
            modelColor: NSColor(calibratedWhite: 0.82, alpha: 1.0),
            backgroundColor: isDark
                ? NSColor(calibratedWhite: 0.16, alpha: 1.0)
                : NSColor(calibratedWhite: 0.93, alpha: 1.0),
            showGroundPlane: true,
            enableShadows: true,
            enableEnvironmentLighting: true,
            useModelColors: useModelColors
        )
    }
}
#endif
