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
import Photos
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

    // MARK: - Load from Recent Photos (test / auto-select)

    /// Queries the system photo library for the most recent photos, then:
    /// - iOS 18+: scores them with Vision aesthetics API via ERVisionHelper
    ///            and picks the highest-scoring image as the portrait.
    /// - iOS 17 and below: picks the most recent photo (first result).
    ///
    /// The selected image is scaled, saved to the App Group container, and returned.
    /// Returns nil if photo library access is denied or no photos are found.
    ///
    /// Call this from the main app only (requires photo library permission).
    @discardableResult
    static func loadFromRecentPhotos(recentCount: Int? = nil) async -> UIImage? {
        // Request photo library access
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            logger.warning("[MasterPortraitStore] Photo library access denied (status: \(status.rawValue)).")
            return nil
        }

        // Fetch the most recent `recentCount` photos
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let recentCount {
            fetchOptions.fetchLimit = recentCount
        }
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let result = PHAsset.fetchAssets(with: fetchOptions)
        guard result.count > 0 else {
            logger.info("[MasterPortraitStore] No photos found in library.")
            return nil
        }

        var identifiers: [String] = []
        result.enumerateObjects { asset, _, _ in
            identifiers.append(asset.localIdentifier)
        }
        logger.info("[MasterPortraitStore] Fetched \(identifiers.count) recent photo identifiers.")

        // Pick the best identifier
        let bestIdentifier: String

        if #available(iOS 18.0, *) {
            // Score with Vision aesthetics API — returns identifiers sorted high→low
            let sorted = await ERVisionHelper.shared.scoreWithVision(imageIdentifiers: identifiers)
            bestIdentifier = sorted.first ?? identifiers[0]
            logger.info("[MasterPortraitStore] Vision scored \(identifiers.count) photos. Best: \(bestIdentifier)")
        } else {
            // Fallback: just use the most recent photo
            bestIdentifier = identifiers[0]
            logger.info("[MasterPortraitStore] iOS < 18 — using most recent photo: \(bestIdentifier)")
        }

        // Load the full image for the chosen asset
        guard let image = await fetchImage(for: bestIdentifier) else {
            logger.error("[MasterPortraitStore] Failed to load image for identifier \(bestIdentifier).")
            return nil
        }

        // Scale and save to App Group container
        let saved = save(image)
        logger.info("[MasterPortraitStore] Auto-selected portrait saved: \(saved). Size: \(image.size.width)×\(image.size.height)px")
        return saved ? load() : nil
    }

    /// Loads a full-resolution image from the photo library for a given asset identifier.
    private static func fetchImage(for identifier: String) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        options.isSynchronous = false

        // Request at the target save size directly to avoid loading a huge image
        let targetSize = CGSize(width: maxPixelDimension, height: maxPixelDimension)

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
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
