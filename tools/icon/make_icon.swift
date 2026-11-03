// Renders the Mantiza app icon (1024 px): the stick sends signal arcs to a pointer that taps the phone.
//   swift tools/icon/make_icon.swift ios/Mantiza/Resources/Assets.xcassets/AppIcon.appiconset
// Writes icon.png (default), icon-dark.png (transparent background) and icon-tinted.png (grayscale).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

enum Variant { case light, dark, tinted }

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}

func gray(_ white: Double, _ alpha: Double = 1) -> CGColor { CGColor(gray: white, alpha: alpha) }

func render(_ variant: Variant) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Draw with a top-left origin.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    let tinted = variant == .tinted
    let accent = tinted ? gray(0.85) : rgb(0x7CFFCB)
    let glyph = tinted ? gray(1) : rgb(0xFFFFFF)

    if variant == .light {
        let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x0A2E25), rgb(0x0E5A47), rgb(0x18A483)] as CFArray,
                                  locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        // Soft glow behind the tap point.
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0x7CFFCB, 0.35), rgb(0x7CFFCB, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 560, y: 300), startRadius: 0,
                               endCenter: CGPoint(x: 560, y: 300), endRadius: 420, options: [])
    }

    // The drawing's own centre is left of the canvas centre.
    ctx.translateBy(x: 45, y: 0)

    // Tap ripples at the pointer tip.
    let tip = CGPoint(x: 560, y: 300)
    ctx.setLineCap(.round)
    for (i, r) in [70.0, 128, 186].enumerated() {
        ctx.setStrokeColor(tinted ? gray(0.9, 0.75 - 0.2 * Double(i)) : rgb(0x7CFFCB, 0.75 - 0.2 * Double(i)))
        ctx.setLineWidth(18 - 4 * Double(i))
        ctx.strokeEllipse(in: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r))
    }

    // The pointer (a classic arrow cursor, tip at the ripple centre).
    let arrow: [(Double, Double)] = [(0, 0), (0, 0.74), (0.19, 0.58), (0.32, 0.88), (0.45, 0.82), (0.32, 0.53), (0.56, 0.53)]
    let scale = 430.0
    let path = CGMutablePath()
    path.addLines(between: arrow.map { CGPoint(x: tip.x + $0.0 * scale, y: tip.y + $0.1 * scale) })
    path.closeSubpath()
    ctx.saveGState()
    if !tinted { ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: rgb(0x00140F, 0.55)) }
    ctx.addPath(path)
    ctx.setFillColor(glyph)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(tinted ? gray(0.55) : rgb(0x0A2E25))
    ctx.setLineWidth(14)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // The stick, tilted, lower left, with its little screen lit.
    ctx.saveGState()
    ctx.translateBy(x: 250, y: 770)
    ctx.rotate(by: -0.5)
    let body = CGPath(roundedRect: CGRect(x: -80, y: -150, width: 160, height: 300), cornerWidth: 46, cornerHeight: 46, transform: nil)
    ctx.addPath(body)
    ctx.setFillColor(tinted ? gray(0.75) : rgb(0xF4FFFB))
    ctx.fillPath()
    let screen = CGPath(roundedRect: CGRect(x: -50, y: -112, width: 100, height: 150), cornerWidth: 20, cornerHeight: 20, transform: nil)
    ctx.addPath(screen)
    ctx.setFillColor(tinted ? gray(0.3) : rgb(0x0A2E25))
    ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: -26, y: 70, width: 52, height: 52))  // button A
    ctx.setFillColor(tinted ? gray(0.45) : rgb(0x18A483))
    ctx.fillPath()
    // A tiny pointer on the stick's screen.
    ctx.setFillColor(accent)
    ctx.fill(CGRect(x: -14, y: -62, width: 28, height: 28))
    ctx.restoreGState()

    // Signal arcs from the stick toward the pointer.
    let origin = CGPoint(x: 330, y: 640)
    for (i, r) in [70.0, 125, 180].enumerated() {
        ctx.setStrokeColor(tinted ? gray(0.9, 0.95 - 0.25 * Double(i)) : rgb(0x7CFFCB, 0.95 - 0.25 * Double(i)))
        ctx.setLineWidth(20)
        ctx.addArc(center: origin, radius: r, startAngle: -.pi * 0.47, endAngle: -.pi * 0.03, clockwise: false)
        ctx.strokePath()
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: out).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print(url.path)
}

write(render(.light), "icon.png")
write(render(.dark), "icon-dark.png")
write(render(.tinted), "icon-tinted.png")
