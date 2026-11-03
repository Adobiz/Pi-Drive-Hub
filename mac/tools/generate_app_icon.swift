// Run with MenuBarModel.swift so all native cloud geometry stays identical.
import AppKit
import SwiftUI

@main struct IconGenerator {
  static func main() throws {
    let root = CommandLine.arguments[1]
    func render(_ pixels: Int) -> Data {
      let image = NSImage(size: NSSize(width: pixels, height: pixels), flipped: true) { _ in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.scaleBy(x: CGFloat(pixels) / 100, y: CGFloat(pixels) / 100)
        let background = CGPath(roundedRect: CGRect(x: 6, y: 6, width: 88, height: 88), cornerWidth: 21, cornerHeight: 21, transform: nil)
        context.saveGState(); context.addPath(background); context.clip()
        let colors = [NSColor(srgbRed: 0.36, green: 0.58, blue: 0.99, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.10, green: 0.29, blue: 0.77, alpha: 1).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 10, y: 6), end: CGPoint(x: 90, y: 96), options: [])
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 2), blur: 2, color: NSColor(srgbRed: 0.07, green: 0.24, blue: 0.62, alpha: 0.28).cgColor)
        context.addPath(CloudGlyph.path(in: CGRect(x: 7, y: 23, width: 86, height: 58)))
        context.setFillColor(NSColor.white.cgColor); context.fillPath(); context.restoreGState()
        context.setStrokeColor(NSColor(srgbRed: 0.18, green: 0.43, blue: 0.93, alpha: 1).cgColor)
        context.setLineWidth(3.7); context.setLineCap(.round); context.setLineJoin(.round)
        context.move(to: CGPoint(x: 41, y: 48)); context.addLine(to: CGPoint(x: 63, y: 48))
        context.move(to: CGPoint(x: 47, y: 49)); context.addCurve(to: CGPoint(x: 44.5, y: 64), control1: CGPoint(x: 47, y: 55), control2: CGPoint(x: 46, y: 60))
        context.move(to: CGPoint(x: 58, y: 49)); context.addLine(to: CGPoint(x: 58, y: 60))
        context.addCurve(to: CGPoint(x: 63, y: 63), control1: CGPoint(x: 58, y: 64), control2: CGPoint(x: 60, y: 65))
        context.strokePath()
        return true
      }
      let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
      return bitmap.representation(using: .png, properties: [:])!
    }
    let iconset = URL(fileURLWithPath: root).appendingPathComponent("macos/Runner/Assets.xcassets/AppIcon.appiconset")
    let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: iconset.appendingPathComponent("Contents.json"))) as! [String: Any]
    for entry in contents["images"] as! [[String: String]] {
      guard let filename = entry["filename"], let size = entry["size"], let scale = entry["scale"] else { continue }
      let pixels = Int(size.split(separator: "x")[0])! * Int(scale.prefix(1))!
      try render(pixels).write(to: iconset.appendingPathComponent(filename))
    }
    try render(1024).write(to: URL(fileURLWithPath: root).appendingPathComponent("assets/PI_Drive_Hub.png"))
  }
}
