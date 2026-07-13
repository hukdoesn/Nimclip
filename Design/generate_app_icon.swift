import AppKit

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let transparentLogoSourceURL = root.appendingPathComponent(
    "Application_logo/Nimclip-touming.png"
)

private let brandRed: UInt8 = 14
private let brandGreen: UInt8 = 30
private let brandBlue: UInt8 = 65

private func loadBitmap(at url: URL) throws -> NSBitmapImageRep {
    guard let data = try? Data(contentsOf: url),
          let bitmap = NSBitmapImageRep(data: data),
          bitmap.samplesPerPixel == 4,
          bitmap.hasAlpha,
          !bitmap.bitmapFormat.contains(.alphaFirst) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return bitmap
}

private func makeRepresentation(
    width: Int,
    height: Int
) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return bitmap
}

private func makePNG(
    size: Int,
    supersample: Int = 1,
    draw: (NSGraphicsContext) -> Void
) throws -> Data {
    let workingSize = size * supersample
    let bitmap = try makeRepresentation(width: workingSize, height: workingSize)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: workingSize, height: workingSize))
    context.cgContext.scaleBy(x: CGFloat(supersample), y: CGFloat(supersample))
    draw(context)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    let output: NSBitmapImageRep
    if supersample == 1 {
        output = bitmap
    } else {
        bitmap.size = NSSize(width: size, height: size)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        let reduced = try makeRepresentation(width: size, height: size)
        guard let reducedContext = NSGraphicsContext(bitmapImageRep: reduced) else {
            throw CocoaError(.fileWriteUnknown)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = reducedContext
        reducedContext.imageInterpolation = .high
        reducedContext.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        reducedContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        output = reduced
    }

    guard let png = output.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

private func cleanMark(from source: NSBitmapImageRep) throws -> NSImage {
    let cleaned = try makeRepresentation(
        width: source.pixelsWide,
        height: source.pixelsHigh
    )
    guard let sourceData = source.bitmapData,
          let cleanedData = cleaned.bitmapData else {
        throw CocoaError(.fileReadCorruptFile)
    }

    var minX = source.pixelsWide
    var minY = source.pixelsHigh
    var maxX = -1
    var maxY = -1

    for y in 0 ..< source.pixelsHigh {
        for x in 0 ..< source.pixelsWide {
            let sourceOffset = y * source.bytesPerRow + x * 4
            let outputOffset = y * cleaned.bytesPerRow + x * 4
            let alpha = CGFloat(sourceData[sourceOffset + 3]) / 255

            let normalized = min(max((alpha - 0.45) / 0.30, 0), 1)
            let coverage = normalized * normalized * (3 - 2 * normalized)
            let alphaByte = UInt8((coverage * 255).rounded())

            cleanedData[outputOffset] = UInt8(Int(brandRed) * Int(alphaByte) / 255)
            cleanedData[outputOffset + 1] = UInt8(Int(brandGreen) * Int(alphaByte) / 255)
            cleanedData[outputOffset + 2] = UInt8(Int(brandBlue) * Int(alphaByte) / 255)
            cleanedData[outputOffset + 3] = alphaByte

            if alphaByte > 4 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
    }

    guard maxX >= minX, maxY >= minY else {
        throw CocoaError(.fileReadCorruptFile)
    }

    let width = maxX - minX + 1
    let height = maxY - minY + 1
    let trimmed = try makeRepresentation(
        width: width,
        height: height
    )
    guard let trimmedData = trimmed.bitmapData else {
        throw CocoaError(.fileWriteUnknown)
    }

    for row in 0 ..< height {
        let sourceOffset = (minY + row) * cleaned.bytesPerRow + minX * 4
        let destinationOffset = row * trimmed.bytesPerRow
        trimmedData.advanced(by: destinationOffset).update(
            from: cleanedData.advanced(by: sourceOffset),
            count: width * 4
        )
    }

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(trimmed)
    return image
}

private func drawMark(
    _ mark: NSImage,
    in canvas: NSRect,
    maximumDimension: CGFloat
) {
    let scale = min(
        maximumDimension / mark.size.width,
        maximumDimension / mark.size.height
    )
    let size = NSSize(
        width: mark.size.width * scale,
        height: mark.size.height * scale
    )
    let destination = NSRect(
        x: canvas.midX - size.width / 2,
        y: canvas.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
    mark.draw(
        in: destination,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func renderTemplateMark(
    size: Int,
    visibleDimension: CGFloat,
    mark: NSImage,
    to url: URL
) throws {
    let png = try makePNG(size: size, supersample: size <= 64 ? 4 : 1) { _ in
        drawMark(
            mark,
            in: NSRect(x: 0, y: 0, width: size, height: size),
            maximumDimension: visibleDimension
        )
    }
    try png.write(to: url)
}

private func renderAppIcon(size: Int, mark: NSImage, to url: URL) throws {
    let png = try makePNG(size: size, supersample: size <= 64 ? 4 : 1) { _ in
        let canvas = NSRect(x: 0, y: 0, width: size, height: size)
        let tileFraction: CGFloat = size <= 32 ? 0.875 : 0.92
        let tileSide = round(CGFloat(size) * tileFraction)
        let tile = NSRect(
            x: canvas.midX - tileSide / 2,
            y: canvas.midY - tileSide / 2,
            width: tileSide,
            height: tileSide
        )
        let path = NSBezierPath(
            roundedRect: tile,
            xRadius: tileSide * 0.22,
            yRadius: tileSide * 0.22
        )

        NSColor(srgbRed: 0.99, green: 0.99, blue: 0.99, alpha: 1).setFill()
        path.fill()

        let markFraction: CGFloat = size <= 32 ? 0.62 : 0.58
        drawMark(
            mark,
            in: canvas,
            maximumDimension: round(tileSide * markFraction)
        )
    }
    try png.write(to: url)
}

let sourceBitmap = try loadBitmap(at: transparentLogoSourceURL)
let mark = try cleanMark(from: sourceBitmap)

let iconDirectory = root.appendingPathComponent("Cliplet/Assets.xcassets/AppIcon.appiconset")
let aboutIconDirectory = root.appendingPathComponent("Cliplet/Assets.xcassets/NimclipAppIcon.imageset")
let markDirectory = root.appendingPathComponent("Cliplet/Assets.xcassets/NimclipMark.imageset")
let menuBarDirectory = root.appendingPathComponent("Cliplet/Assets.xcassets/NimclipMenuBar.imageset")
try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: aboutIconDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: markDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: menuBarDirectory, withIntermediateDirectories: true)

let appIconSizes: [(Int, String)] = [
    (16, "app-icon-16.png"),
    (32, "app-icon-16@2x.png"),
    (32, "app-icon-32.png"),
    (64, "app-icon-32@2x.png"),
    (128, "app-icon-128.png"),
    (256, "app-icon-128@2x.png"),
    (256, "app-icon-256.png"),
    (512, "app-icon-256@2x.png"),
    (512, "app-icon.png"),
    (1024, "app-icon@2x.png")
]
for (size, filename) in appIconSizes {
    try renderAppIcon(
        size: size,
        mark: mark,
        to: iconDirectory.appendingPathComponent(filename)
    )
}

try renderAppIcon(
    size: 512,
    mark: mark,
    to: aboutIconDirectory.appendingPathComponent("nimclip-app-icon.png")
)
try renderTemplateMark(
    size: 1024,
    visibleDimension: 800,
    mark: mark,
    to: markDirectory.appendingPathComponent("nimclip-mark.png")
)
try renderTemplateMark(
    size: 18,
    visibleDimension: 14,
    mark: mark,
    to: menuBarDirectory.appendingPathComponent("nimclip-menubar.png")
)
try renderTemplateMark(
    size: 36,
    visibleDimension: 28,
    mark: mark,
    to: menuBarDirectory.appendingPathComponent("nimclip-menubar@2x.png")
)
