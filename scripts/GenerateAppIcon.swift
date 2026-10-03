import AppKit
import Foundation

private let canvasSize = 1024

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

private func drawIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 18, dy: 18), xRadius: 218, yRadius: 218)
    let backgroundGradient = NSGradient(colors: [
        color(0.035, 0.12, 0.29),
        color(0.075, 0.12, 0.36),
        color(0.18, 0.10, 0.36),
    ])!
    backgroundGradient.draw(in: background, angle: 132)

    let clockRect = CGRect(x: 150, y: 150, width: 724, height: 724)
    let clockFace = NSBezierPath(ovalIn: clockRect)
    let faceGradient = NSGradient(colors: [color(0.095, 0.18, 0.35), color(0.035, 0.09, 0.22)])!
    faceGradient.draw(in: clockFace, angle: 120)
    color(0.50, 0.80, 0.94, 0.25).setStroke()
    clockFace.lineWidth = 4
    clockFace.stroke()

    let center = CGPoint(x: 512, y: 512)
    let outerRingRect = CGRect(x: 190, y: 190, width: 644, height: 644)
    let outerRing = NSBezierPath(ovalIn: outerRingRect)
    outerRing.lineWidth = 29
    color(0.44, 0.62, 0.78, 0.22).setStroke()
    outerRing.stroke()

    let progress = NSBezierPath()
    progress.lineCapStyle = .round
    progress.lineJoinStyle = .round
    progress.lineWidth = 31
    progress.appendArc(withCenter: center, radius: 322, startAngle: -90, endAngle: 174, clockwise: false)
    color(0.31, 0.91, 0.78).setStroke()
    progress.stroke()

    // A small warm endpoint gives the progress ring a clear direction.
    let endpointAngle = CGFloat(174) * .pi / 180
    let endpoint = CGPoint(x: center.x + cos(endpointAngle) * 322, y: center.y + sin(endpointAngle) * 322)
    color(1.0, 0.67, 0.34).setFill()
    NSBezierPath(ovalIn: CGRect(x: endpoint.x - 13, y: endpoint.y - 13, width: 26, height: 26)).fill()

    // Hour marks keep the face legible at small dock sizes without adding numerals.
    for index in 0..<12 {
        let angle = CGFloat(index) * .pi / 6
        let isQuarter = index.isMultiple(of: 3)
        let radius: CGFloat = isQuarter ? 272 : 280
        let markWidth: CGFloat = isQuarter ? 15 : 10
        let markHeight: CGFloat = isQuarter ? 43 : 25
        let markCenter = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        let tangent = CGPoint(x: -sin(angle), y: cos(angle))
        let start = CGPoint(x: markCenter.x - tangent.x * markHeight / 2, y: markCenter.y - tangent.y * markHeight / 2)
        let end = CGPoint(x: markCenter.x + tangent.x * markHeight / 2, y: markCenter.y + tangent.y * markHeight / 2)
        let mark = NSBezierPath()
        mark.lineCapStyle = .round
        mark.lineWidth = markWidth
        mark.move(to: start)
        mark.line(to: end)
        color(0.80, 0.91, 0.98, isQuarter ? 0.96 : 0.49).setStroke()
        mark.stroke()
    }

    func hand(to point: CGPoint, width: CGFloat, shade: NSColor) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineWidth = width
        path.move(to: center)
        path.line(to: point)
        shade.setStroke()
        path.stroke()
    }

    hand(to: CGPoint(x: 365, y: 657), width: 31, shade: color(0.93, 0.97, 1))
    hand(to: CGPoint(x: 681, y: 651), width: 22, shade: color(0.38, 0.95, 0.82))
    hand(to: CGPoint(x: 512, y: 401), width: 12, shade: color(1.0, 0.67, 0.34))

    color(0.99, 0.99, 1).setFill()
    NSBezierPath(ovalIn: CGRect(x: 485, y: 485, width: 54, height: 54)).fill()
    color(0.38, 0.95, 0.82).setFill()
    NSBezierPath(ovalIn: CGRect(x: 497, y: 497, width: 30, height: 30)).fill()

    return image
}

private func pngData(from image: NSImage, size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
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

let icon = drawIcon()
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
    try pngData(from: icon, size: size).write(to: iconsetURL.appendingPathComponent(filename), options: .atomic)
}
try pngData(from: icon, size: canvasSize).write(to: outputDirectory.appendingPathComponent("ProductivityTime-Icon-Preview.png"), options: .atomic)
try writeICNS(to: outputDirectory.appendingPathComponent("ProductivityTime.icns"), iconsetURL: iconsetURL)
print("Generated iconset and preview at \(outputDirectory.path)")
