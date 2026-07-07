import AppKit

// Renders the XCBuildStats app icon (a build-time bar chart) to a 1024x1024 PNG.
// Usage: swift scripts/generate-icon.swift <output.png>

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Rounded-square container (macOS-style padding for shadow).
let margin: CGFloat = 84
let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let radius: CGFloat = 200
let container = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Blue → indigo diagonal gradient.
ctx.saveGState()
ctx.addPath(container)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(calibratedRed: 0.29, green: 0.56, blue: 0.99, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.09, green: 0.20, blue: 0.52, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: rect.minX, y: rect.maxY),
    end: CGPoint(x: rect.maxX, y: rect.minY),
    options: []
)
ctx.restoreGState()

// Ascending bar chart in white.
let chart = rect.insetBy(dx: rect.width * 0.24, dy: rect.height * 0.26)
let heights: [CGFloat] = [0.32, 0.58, 0.86, 0.50]
let gap = chart.width * 0.09
let barWidth = (chart.width - gap * CGFloat(heights.count - 1)) / CGFloat(heights.count)
for (index, fraction) in heights.enumerated() {
    let x = chart.minX + CGFloat(index) * (barWidth + gap)
    let barRect = CGRect(x: x, y: chart.minY, width: barWidth, height: chart.height * fraction)
    let corner = barWidth * 0.3
    ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95 - CGFloat(index) * 0.06).cgColor)
    ctx.fillPath()
}

NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
