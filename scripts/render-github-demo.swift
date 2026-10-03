import AppKit
import Foundation
import ImageIO

private struct DemoScene {
    let slug: String
    let eyebrow: String
    let title: String
    let detail: String
    let showsDemoDataNote: Bool
}

@MainActor
private enum GitHubDemoRenderer {
    static let canvasSize = NSSize(width: 1_200, height: 850)
    static let scenes = [
        DemoScene(
            slug: "activities",
            eyebrow: "ACTIVITIES",
            title: "Name the work you're tracking",
            detail: "Create separate activities and pick what to focus on.",
            showsDemoDataNote: false
        ),
        DemoScene(
            slug: "stopwatch",
            eyebrow: "STOPWATCH",
            title: "Track and pause a stopwatch",
            detail: "Resume the same session when you're ready to focus again.",
            showsDemoDataNote: false
        ),
        DemoScene(
            slug: "complete",
            eyebrow: "COMPLETED SESSIONS",
            title: "Complete to save your session",
            detail: "Finished sessions appear in History with separate destination states.",
            showsDemoDataNote: true
        ),
        DemoScene(
            slug: "timer",
            eyebrow: "COUNTDOWN TIMER",
            title: "Pick a timer preset",
            detail: "Choose 5, 25, or 50 minutes, or set a custom duration.",
            showsDemoDataNote: false
        ),
        DemoScene(
            slug: "history",
            eyebrow: "SESSION HISTORY",
            title: "See each destination's delivery status",
            detail: "Apple Notes and Notion keep separate status and retry state.",
            showsDemoDataNote: true
        )
    ]

    static func run() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let captureDirectory = root.appendingPathComponent(".build/demo-captures", isDirectory: true)
        let workDirectory = root.appendingPathComponent(".build/github-demo", isDirectory: true)
        let outputDirectory = root.appendingPathComponent("docs/media", isDirectory: true)

        guard FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") || executableOnPath("ffmpeg") != nil else {
            throw DemoError.message("ffmpeg is required. Install it inside the project environment and ensure it is on PATH.")
        }

        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var frameURLs: [URL] = []
        for (index, scene) in scenes.enumerated() {
            let capture = captureDirectory.appendingPathComponent(String(format: "%02d.png", index + 1))
            guard FileManager.default.fileExists(atPath: capture.path) else {
                throw DemoError.message("Missing real app capture: \(capture.path) (expected captures 01.png through 05.png).")
            }
            let frame = workDirectory.appendingPathComponent(String(format: "%02d-%@.png", index + 1, scene.slug))
            try render(capture: capture, scene: scene, index: index + 1, into: frame)
            frameURLs.append(frame)
        }

        let concatManifest = workDirectory.appendingPathComponent("scenes.txt")
        try writeConcatManifest(frameURLs: frameURLs, to: concatManifest)

        let gif = outputDirectory.appendingPathComponent("productivity-time-demo.gif")
        let mp4 = outputDirectory.appendingPathComponent("productivity-time-demo.mp4")
        try makeGIF(manifest: concatManifest, destination: gif)
        try makeMP4(manifest: concatManifest, destination: mp4)

        let gifBytes = try fileSize(at: gif)
        let mp4Bytes = try fileSize(at: mp4)
        print("Created \(gif.path) (\(formattedBytes(gifBytes)))")
        print("Created \(mp4.path) (\(formattedBytes(mp4Bytes)))")
        if gifBytes >= 8 * 1_024 * 1_024 {
            throw DemoError.message("GIF is \(formattedBytes(gifBytes)); GitHub target is below 8 MB. Reduce the capture dimensions or GIF frame rate and rerun.")
        }
    }

    private static func render(capture: URL, scene: DemoScene, index: Int, into destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(capture as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DemoError.message("Could not read PNG capture at \(capture.path).")
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw DemoError.message("Could not allocate the 1200×850 RGBA output bitmap.")
        }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw DemoError.message("Could not allocate the 1200×850 output canvas.")
        }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        let canvas = NSRect(origin: .zero, size: canvasSize)
        fill(color: color(0.955, 0.965, 0.950), rect: canvas)

        // Brand and step indicator make each still read as one chapter of a short walkthrough.
        roundedRect(NSRect(x: 48, y: 817, width: 12, height: 12), radius: 4, fill: color(0.31, 0.49, 0.37))
        drawText("PRODUCTIVITY TIME", x: 69, y: 813, size: 12, weight: .bold, color: color(0.31, 0.40, 0.34), tracking: 1.4)
        drawText(scene.eyebrow, x: 842, y: 814, size: 10, weight: .semibold, color: color(0.49, 0.55, 0.50), tracking: 0.8)
        let step = String(format: "%02d / %02d", index, scenes.count)
        drawText(step, x: 1080, y: 813, size: 12, weight: .semibold, color: color(0.49, 0.55, 0.50), tracking: 0.8)

        drawText(scene.title, x: 48, y: 758, size: 31, weight: .bold, color: color(0.13, 0.18, 0.15))
        drawText(scene.detail, x: 50, y: 732, size: 15, weight: .regular, color: color(0.40, 0.46, 0.42))

        let card = NSRect(x: 30, y: 91, width: 1_140, height: 610)
        let shadow = NSShadow()
        shadow.shadowColor = color(0.15, 0.20, 0.16, alpha: 0.12)
        shadow.shadowOffset = NSSize(width: 0, height: -9)
        shadow.shadowBlurRadius = 22
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        roundedRect(card, radius: 15, fill: .white)
        NSGraphicsContext.restoreGraphicsState()
        roundedRect(card, radius: 15, fill: .white, stroke: color(0.86, 0.89, 0.86), lineWidth: 1)

        let imageArea = NSRect(x: 47, y: 108, width: 1_106, height: 576)
        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)
        let fitScale = min(imageArea.width / sourceWidth, imageArea.height / sourceHeight)
        let fittedSize = NSSize(width: sourceWidth * fitScale, height: sourceHeight * fitScale)
        let fittedRect = NSRect(
            x: imageArea.midX - fittedSize.width / 2,
            y: imageArea.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: imageArea, xRadius: 9, yRadius: 9).addClip()
        NSImage(cgImage: cgImage, size: NSSize(width: sourceWidth, height: sourceHeight))
            .draw(in: fittedRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        if scene.showsDemoDataNote {
            drawText("DEMO DATA · DELIVERY STATUSES ARE EXAMPLES", x: 48, y: 55, size: 9, weight: .medium, color: color(0.53, 0.58, 0.54), tracking: 0.7)
        }

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw DemoError.message("Could not encode rendered frame \(destination.path).")
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func makeGIF(manifest: URL, destination: URL) throws {
        let filter = "[0:v]fps=12,split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
        try runFFmpeg([
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "1", "-i", manifest.path,
            "-filter_complex", filter,
            "-loop", "0", "-t", "20", "-gifflags", "+transdiff",
            destination.path
        ])
    }

    private static func makeMP4(manifest: URL, destination: URL) throws {
        try runFFmpeg([
            "-y", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "1", "-i", manifest.path,
            "-vf", "fps=30,format=yuv420p",
            "-c:v", "libx264", "-preset", "slow", "-crf", "22",
            "-movflags", "+faststart", "-t", "20",
            destination.path
        ])
    }

    private static func writeConcatManifest(frameURLs: [URL], to url: URL) throws {
        var lines = frameURLs.flatMap { ["file '\($0.lastPathComponent)'", "duration 4"] }
        lines.append("file '\(frameURLs[frameURLs.count - 1].lastPathComponent)'")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func runFFmpeg(_ arguments: [String]) throws {
        let executable = executableOnPath("ffmpeg") ?? "/opt/homebrew/bin/ffmpeg"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DemoError.message("ffmpeg exited with status \(process.terminationStatus).")
        }
    }

    private static func executableOnPath(_ name: String) -> String? {
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate.path }
        }
        return nil
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        String(format: "%.2f MB", Double(bytes) / 1_024 / 1_024)
    }

    private static func drawText(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor, tracking: CGFloat = 0) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]
        if tracking != 0 { attributes[.kern] = tracking }
        NSAttributedString(string: value, attributes: attributes).draw(at: NSPoint(x: x, y: y))
    }

    private static func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 0) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        if let stroke {
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        } else {
            fill.setFill()
            path.fill()
        }
    }

    private static func fill(color: NSColor, rect: NSRect) {
        color.setFill()
        rect.fill()
    }

    private static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private enum DemoError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(value): value
        }
    }
}

do {
    try MainActor.assumeIsolated {
        try GitHubDemoRenderer.run()
    }
} catch {
    fputs("GitHub demo render failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
