import QuickLookThumbnailing
import ThreeMFKit
import AppKit
import SceneKit
import Metal

final class ThumbnailProvider: QLThumbnailProvider {
    /// Wall-clock budget for the SceneKit fallback path (mesh parse +
    /// render); Quick Look kills extensions that run far longer than this,
    /// so bail out cooperatively well before that happens.
    private static let renderDeadline: TimeInterval = 20
    /// Above this, rendering (and even building the SceneKit geometry) gets
    /// noticeably slower; QL thumbnails don't need every triangle.
    private static let maxThumbnailTriangles = 3_000_000
    /// Meshes above this size get a cheaper antialiasing mode to keep the
    /// snapshot render within the time budget.
    private static let highTriangleAntialiasingThreshold = 1_000_000

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        // Fast path: draw the slicer-embedded PNG thumbnail directly, no mesh parsing.
        if let reply = fastPathReply(for: request) {
            handler(reply, nil)
            return
        }

        // Fallback: parse the mesh and render an offscreen SceneKit snapshot.
        do {
            let reply = try renderedSceneReply(for: request)
            handler(reply, nil)
        } catch {
            // Report the failure (rather than silent nil/nil) so Quick Look
            // falls back to the default file icon instead of retrying forever.
            handler(nil, error)
        }
    }

    private func fastPathReply(for request: QLFileThumbnailRequest) -> QLThumbnailReply? {
        guard
            let data = try? ModelLoader(options: .thumbnailOnly).extractPrimaryThumbnail(url: request.fileURL),
            let image = NSImage(data: data)
        else {
            return nil
        }

        let contextSize = request.maximumSize
        return QLThumbnailReply(contextSize: contextSize) { () -> Bool in
            Self.drawAspectFit(image: image, in: contextSize)
            return true
        }
    }

    private func renderedSceneReply(for request: QLFileThumbnailRequest) throws -> QLThumbnailReply? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let deadline = Date().addingTimeInterval(Self.renderDeadline)
        var options = ThreeMFLoader.Options.default
        options.maxTriangles = Self.maxThumbnailTriangles
        options.shouldCancel = { Date() > deadline }

        let document = try ModelLoader(options: options).load(url: request.fileURL)
        guard let plate = document.plates.first else { return nil }

        let scene = plate.makeScene()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.previewCameraNode

        let pixelSize = CGSize(
            width: request.maximumSize.width * request.scale,
            height: request.maximumSize.height * request.scale
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let antialiasingMode: SCNAntialiasingMode =
            plate.mesh.triangleCount > Self.highTriangleAntialiasingThreshold ? .none : .multisampling4X
        let cgImage = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: antialiasingMode).cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        )
        guard let cgImage else { return nil }

        let contextSize = request.maximumSize
        return QLThumbnailReply(contextSize: contextSize) { () -> Bool in
            let context = NSGraphicsContext.current?.cgContext
            context?.draw(cgImage, in: CGRect(origin: .zero, size: contextSize))
            return true
        }
    }

    /// Draws `image` centered and aspect-fit within `size` in the current graphics context.
    private static func drawAspectFit(image: NSImage, in size: CGSize) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)

        image.draw(in: CGRect(origin: origin, size: drawSize), from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
