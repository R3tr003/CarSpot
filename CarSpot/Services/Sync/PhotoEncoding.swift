import UIKit

/// Codifica delle foto per cache locale e Storage: lato lungo limitato + JPEG compresso
/// (~150–250 KB). Lo stesso dato va in SwiftData e nel bucket.
enum PhotoEncoding {
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }
        // Mai ingrandire.
        guard longest > maxSide else { return image.jpegData(compressionQuality: quality) }

        let ratio = maxSide / longest
        let target = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
