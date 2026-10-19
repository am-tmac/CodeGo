import AppKit
// Quick Look's SVG thumbnail may occupy only a corner of its canvas. Recover the
// monochrome coverage, preserve aspect ratio, and center it at the SVG's 76% extent.
let args = CommandLine.arguments
let source = URL(fileURLWithPath: args[1])
let target = URL(fileURLWithPath: args[2])
let sourceRep = NSBitmapImageRep(data: try Data(contentsOf: source))!
var minX = sourceRep.pixelsWide, minY = sourceRep.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<sourceRep.pixelsHigh { for x in 0..<sourceRep.pixelsWide {
    if sourceRep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!.redComponent < 0.95 {
        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
    }
}}
let width = Double(maxX - minX + 1), height = Double(maxY - minY + 1)
for scale in 1...3 {
    let size = 64 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    let factor = Double(size) * 0.76 / max(width, height)
    let offsetX = (Double(size) - width * factor) / 2
    let offsetY = (Double(size) - height * factor) / 2
    for y in 0..<size { for x in 0..<size {
        let sx = Int(floor((Double(x) - offsetX) / factor)) + minX
        let sy = Int(floor((Double(y) - offsetY) / factor)) + minY
        let alpha: CGFloat
        if sx >= minX && sx <= maxX && sy >= minY && sy <= maxY {
            alpha = 1 - sourceRep.colorAt(x: sx, y: sy)!.usingColorSpace(.deviceRGB)!.redComponent
        } else { alpha = 0 }
        rep.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: alpha), atX: x, y: y)
    }}
    let suffix = scale == 1 ? "" : "@\(scale)x"
    try rep.representation(using: .png, properties: [:])!.write(to: target.deletingLastPathComponent().appendingPathComponent(target.lastPathComponent + suffix + ".png"))
}
