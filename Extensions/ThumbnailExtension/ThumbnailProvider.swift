import QuickLookThumbnailing
import ThreeMFKit
import AppKit
import SceneKit
import Metal

final class ThumbnailProvider: QLThumbnailProvider {
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
        if let reply = renderedSceneReply(for: request) {
            handler(reply, nil)
            return
        }

        handler(nil, nil)
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

    private func renderedSceneReply(for request: QLFileThumbnailRequest) -> QLThumbnailReply? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        guard let document = try? ModelLoader().load(url: request.fileURL),
              let plate = document.plates.first
        else {
            return nil
        }

        let scene = plate.makeScene()
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene

        let pixelSize = CGSize(
            width: request.maximumSize.width * request.scale,
            height: request.maximumSize.height * request.scale
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else { return nil }

        let cgImage = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X).cgImage(
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
