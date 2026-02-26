/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Saves and loads the owner/master portrait image shared between the app
and the widget extension via the App Group container.

Key constraints for Live Activity images (Apple HIG):
- Image must be loaded from a file path, NOT passed through ContentState
  (ContentState has a 4KB limit — images blow through this immediately)
- Image pixel size must be within Live Activity presentation limits.
  Lock Screen banner: ~160×160 pt max for a portrait circle at 36pt display size
  → at 3x scale = 108×108 px is more than sufficient
- The file must exist in the shared App Group container BEFORE the
  Live Activity starts. The widget extension reads it at render time
  via UIImage(contentsOfFile:).
*/

import UIKit
import OSLog

private let logger = Logger(subsystem: "MasterPortraitStore", category: "Storage")

enum MasterPortraitStore {

    static let fileName = "master_portrait.jpg"

    // Max pixel dimension written to disk. 108px = 36pt @3x — enough for the
    // circular portrait in the Live Activity. Keeps file size small (~5–15KB).
    // 200 will not display in live-activity, but 180 is fine. HIG says 160pt max at 3x = 480px, but in practice the live activity seems to reject anything above ~200px.
    private static let maxPixelDimension: CGFloat = 180
    private static let compressionQuality: CGFloat = 0.8

    // MARK: - Shared container URL

    static var fileURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: EmojiRanger.appGroup) else {
            logger.error("""
                [MasterPortraitStore] App Group container not found for '\(EmojiRanger.appGroup)'.
                Ensure App Groups capability is enabled in Xcode Signing & Capabilities
                for BOTH the app target and EmojiRangerWidgetExtension target.
                """)
            return nil
        }
        return container.appendingPathComponent(fileName)
    }

    // MARK: - Save

    /// Downscales the image to 108×108 px max and saves as JPEG to the App Group container.
    /// Must be called from the main app before starting a Live Activity.
    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        guard let url = fileURL else { return false }

        let scaled = image.scaledToSquare(maxPixels: maxPixelDimension)
        guard let data = scaled.jpegData(compressionQuality: compressionQuality) else {
            logger.error("[MasterPortraitStore] JPEG encoding failed.")
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            logger.info("[MasterPortraitStore] Saved \(data.count) bytes → \(url.path)")
            return true
        } catch {
            logger.error("[MasterPortraitStore] Write failed: \(error)")
            return false
        }
    }

    // MARK: - Load

    /// Loads the portrait from the App Group container.
    /// Safe to call from both the app and the widget extension.
    static func load() -> UIImage? {
        guard let url = fileURL else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.info("[MasterPortraitStore] No portrait file at \(url.path)")
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            logger.error("[MasterPortraitStore] Failed to read image at \(url.path)")
            return nil
        }
        logger.info("[MasterPortraitStore] Loaded \(data.count) bytes, size \(image.size.width)×\(image.size.height)px")
        return image
    }

    // MARK: - Delete

    static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
        logger.info("[MasterPortraitStore] Deleted portrait.")
    }

    static var exists: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - UIImage scaling

private extension UIImage {
    /// Crops to a centre square then scales down to maxPixels × maxPixels.
    func scaledToSquare(maxPixels: CGFloat) -> UIImage {
        // 1. Crop to square from centre
        let side = min(size.width, size.height)
        let cropRect = CGRect(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2,
            width: side,
            height: side
        )
        let targetSize = CGSize(width: maxPixels, height: maxPixels)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            // Draw the cropped region scaled into the target square
            let drawRect = CGRect(
                x: -(cropRect.origin.x * maxPixels / side),
                y: -(cropRect.origin.y * maxPixels / side),
                width: size.width * maxPixels / side,
                height: size.height * maxPixels / side
            )
            self.draw(in: drawRect)
        }
    }
}
