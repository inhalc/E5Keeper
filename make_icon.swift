import AppKit
import Foundation

// 生成 1024x1024 图标：渐变圆角底 + 白色循环箭头
let size = 1024.0
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let path = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 200, yRadius: 200)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.10, green: 0.42, blue: 0.94, alpha: 1),
    NSColor(srgbRed: 0.09, green: 0.72, blue: 0.66, alpha: 1)
])!
gradient.draw(in: path, angle: -60)

// 白色循环箭头
if let symbol = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
    let cfg = NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold)
    if let img = symbol.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: img.size)
        tinted.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: img.size))
        NSColor.white.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        tinted.unlockFocus()

        let s = tinted.size
        let scale = min(600 / s.width, 600 / s.height)
        let w = s.width * scale
        let h = s.height * scale
        let target = NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

ctx.flush()
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
if let data = rep.representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
