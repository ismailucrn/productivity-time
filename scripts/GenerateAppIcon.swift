import AppKit
import Foundation

private let canvasSize = 1024
private let sourceFilename = "ProductivityTime-Icon-Source.png"
// The source-art bounds are measured from its top-left origin and converted
// to AppKit's bottom-left coordinate system, then inset to clip alpha fringe.
private let sourceTile = CGRect(x: 112, y: 128, width: 1032, height: 1012)
private let sourceTileRadius: CGFloat = 222

private func loadSourceIcon() throws -> (NSImage, Data, Int) {
    let scriptURL = URL(fileURLWithPath: #filePath)
    let resourcesURL = scriptURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("ProductivityTime/Resources", isDirectory: true)
    let sourceURL = resourcesURL.appendingPathComponent(sourceFilename)
    let sourceData = try Data(contentsOf: sourceURL)
    guard let bitmap = NSBitmapImageRep(data: sourceData),
          bitmap.pixelsWide == bitmap.pixelsHigh,
          let image = NSImage(data: sourceData) else {
        throw NSError(
            domain: "ProductivityTimeIcon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Expected a square PNG at \(sourceURL.path)."]
        )
    }
    return (image, sourceData, bitmap.pixelsWide)
}

private func pngData(from image: NSImage, size: Int, sourcePixelSize: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(size) / CGFloat(sourcePixelSize)
    let tileRect = CGRect(
        x: sourceTile.minX * scale,
        y: sourceTile.minY * scale,
        width: sourceTile.width * scale,
        height: sourceTile.height * scale
    )
    NSBezierPath(
        roundedRect: tileRect,
        xRadius: sourceTileRadius * scale,
        yRadius: sourceTileRadius * scale
    ).addClip()
    image.draw(in: CGRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ProductivityTimeIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG icon."])
    }
    return data
}

private func appendBigEndian(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

private func writeICNS(to url: URL, iconsetURL: URL) throws {
    let images: [(String, String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]
    var payload = Data()
    for (type, filename) in images {
        let imageData = try Data(contentsOf: iconsetURL.appendingPathComponent(filename))
        payload.append(contentsOf: type.utf8)
        appendBigEndian(UInt32(imageData.count + 8), to: &payload)
        payload.append(imageData)
    }

    var container = Data("icns".utf8)
    appendBigEndian(UInt32(payload.count + 8), to: &container)
    container.append(payload)
    try container.write(to: url, options: .atomic)
}

let outputDirectory = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ProductivityTime/Resources", isDirectory: true).standardizedFileURL
let iconsetURL = outputDirectory.appendingPathComponent("ProductivityTime.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let (icon, _, sourcePixelSize) = try loadSourceIcon()
let representations: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (size, filename) in representations {
    try pngData(from: icon, size: size, sourcePixelSize: sourcePixelSize).write(to: iconsetURL.appendingPathComponent(filename), options: .atomic)
}
try pngData(from: icon, size: canvasSize, sourcePixelSize: sourcePixelSize)
    .write(to: outputDirectory.appendingPathComponent("ProductivityTime-Icon-Preview.png"), options: .atomic)
try writeICNS(to: outputDirectory.appendingPathComponent("ProductivityTime.icns"), iconsetURL: iconsetURL)
print("Generated iconset from \(sourceFilename) at \(outputDirectory.path)")
