import SwiftUI

/// Mantiza's look (from images/: o1-gridded, o6-lockup, pixel-sheet): near-black ink, magenta and
/// neon green pixels, square corners, thin lines, monospaced type.
public enum Theme {
    public static let ink = Color(hex: 0x0D0A12)       // background (the logos' background)
    public static let panel = Color(hex: 0x14101A)     // a step lighter, for panels
    public static let line = Color(hex: 0x2A2333)      // hairlines and borders
    public static let magenta = Color(hex: 0xD701A5)   // the head
    public static let green = Color(hex: 0x02F34C)     // antennae, eyes, the Z
    public static let text = Color(hex: 0xEEEAF4)
    public static let dim = Color(hex: 0x8A8394)

    /// Corners stay sharp, like the pixels.
    public static let corner: CGFloat = 2

    public static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
