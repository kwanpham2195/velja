// Draws Velja's app icon as a 1024×1024 PNG: a white branching-arrow symbol on a teal-to-indigo
// rounded square. Run through scripts/generate-app-icon.sh, which turns the PNG into AppIcon.icns.
//
// Usage: swift scripts/generate-app-icon.swift <output.png>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift <output.png>\n".utf8))
    exit(64)
}
let outputURL = URL(filePath: arguments[1])

let canvasSize = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvasSize, pixelsHigh: canvasSize, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("generate-app-icon: could not create a bitmap context\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

// macOS icon grid: the rounded square is 824 points wide, centered, leaving room for the shadow.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.08, green: 0.72, blue: 0.65, alpha: 1),
    ending: NSColor(srgbRed: 0.31, green: 0.27, blue: 0.90, alpha: 1)
)
gradient?.draw(in: tilePath, angle: -60)

let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfiguration) else {
    FileHandle.standardError.write(Data("generate-app-icon: SF Symbol arrow.triangle.branch is unavailable\n".utf8))
    exit(1)
}
let symbolSize = symbol.size
let symbolRect = NSRect(
    x: tileRect.midX - symbolSize.width / 2,
    y: tileRect.midY - symbolSize.height / 2,
    width: symbolSize.width,
    height: symbolSize.height
)
symbol.draw(in: symbolRect)

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("generate-app-icon: could not encode PNG\n".utf8))
    exit(1)
}
do {
    try pngData.write(to: outputURL)
} catch {
    FileHandle.standardError.write(Data("generate-app-icon: could not write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
