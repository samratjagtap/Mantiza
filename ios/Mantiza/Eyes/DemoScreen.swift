import UIKit

/// Draws a simple Settings-like screen with known text: demo frames for the Simulator and OCR tests.
enum DemoScreen {
    static let rows = ["General", "Accessibility", "Camera", "Display & Brightness", "Wallpaper", "Battery", "Privacy & Security"]

    @MainActor static func settings(size: CGSize = CGSize(width: 390, height: 844), scale: CGFloat = 2) -> CGImage {
        list(title: "Settings", rows: rows, size: size, scale: scale)
    }

    /// A titled list screen; row i is drawn at y = 170 + 52 i points (row centre 194 + 52 i).
    @MainActor static func list(title titleText: String, rows: [String], size: CGSize = CGSize(width: 390, height: 844),
                                scale: CGFloat = 2) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemGroupedBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 34), .foregroundColor: UIColor.black]
            (titleText as NSString).draw(at: CGPoint(x: 20, y: 100), withAttributes: title)
            let row: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black]
            for (i, text) in rows.enumerated() {
                let y = 170 + CGFloat(i) * 52
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 16, y: y, width: size.width - 32, height: 48))
                (text as NSString).draw(at: CGPoint(x: 32, y: y + 13), withAttributes: row)
            }
        }
        return image.cgImage!
    }
}
