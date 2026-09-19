import AppKit
import QuickLookThumbnailing

/// Renders real content previews (actual image content, a PDF's first page, etc.) the same
/// way Finder does, instead of a generic file-type icon.
enum ThumbnailLoader {
    static func loadThumbnail(for url: URL, pointSize: CGFloat, completion: @escaping (NSImage) -> Void) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: pointSize, height: pointSize)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
            guard let representation, error == nil else { return }
            DispatchQueue.main.async {
                completion(representation.nsImage)
            }
        }
    }
}
