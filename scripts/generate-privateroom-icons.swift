#!/usr/bin/env swift
// Original repo-native geometric artwork. Run from the repository root on macOS.
// This renders the same speech-bubble/door geometry as PrivateRoomMark and its SVG.
import AppKit
import Foundation
import ImageIO

let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDirectory = repository.appendingPathComponent("PrivateChat/Assets.xcassets/AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: iconDirectory.appendingPathComponent("Contents.json"))) as! [String: Any]
let images = manifest["images"] as! [[String: String]]
let ink = NSColor(srgbRed: 0.04, green: 0.08, blue: 0.10, alpha: 1)
let elevated = NSColor(srgbRed: 0.07, green: 0.13, blue: 0.15, alpha: 1)
let mint = NSColor(srgbRed: 0.62, green: 0.91, blue: 0.80, alpha: 1)
let ivory = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.90, alpha: 1)

func render(side: Int) throws -> Data {
    let size = CGFloat(side)
    // RGBX is a supported CoreGraphics drawing format. The skipped channel is
    // not alpha; ImageIO emits an opaque RGB PNG for App Store icon validation.
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let drawingContext = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw NSError(domain: "PrivateRoomArtwork", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: drawingContext, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    ink.setFill()
    canvas.fill()
    NSGradient(starting: elevated, ending: ink)!.draw(in: canvas, angle: -70)
    // A 100-unit vector inset within the app-icon canvas; the OS applies masking.
    let span = size * 0.72
    let originX = size * 0.14
    let originY = size * 0.13
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: originX + x / 100 * span, y: size - originY - y / 100 * span)
    }
    func rectangle(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: originX + x / 100 * span, y: size - originY - (y + height) / 100 * span, width: width / 100 * span, height: height / 100 * span)
    }
    let bubble = NSBezierPath()
    bubble.move(to: point(25, 14))
    bubble.line(to: point(75, 14))
    bubble.curve(to: point(88, 27), controlPoint1: point(83.667, 14), controlPoint2: point(88, 18.333))
    bubble.line(to: point(88, 64))
    bubble.curve(to: point(75, 77), controlPoint1: point(88, 72.667), controlPoint2: point(83.667, 77))
    bubble.line(to: point(45, 77))
    bubble.line(to: point(24, 90))
    bubble.line(to: point(24, 77))
    bubble.curve(to: point(12, 64), controlPoint1: point(16, 77), controlPoint2: point(12, 72.667))
    bubble.line(to: point(12, 27))
    bubble.curve(to: point(25, 14), controlPoint1: point(12, 18.333), controlPoint2: point(16.333, 14))
    bubble.lineWidth = span * 0.055
    bubble.lineCapStyle = .round
    bubble.lineJoinStyle = .round
    mint.setStroke()
    bubble.stroke()
    ivory.setFill()
    NSBezierPath(roundedRect: rectangle(35.5, 25.5, 29, 39), xRadius: span * 0.045, yRadius: span * 0.045).fill()
    ink.setFill()
    NSBezierPath(roundedRect: rectangle(42.5, 33.5, 17, 32), xRadius: span * 0.025, yRadius: span * 0.025).fill()
    mint.setFill()
    NSBezierPath(ovalIn: rectangle(52.75, 45.75, 2.5, 2.5)).fill()
    guard let cgImage = drawingContext.makeImage() else { throw NSError(domain: "PrivateRoomArtwork", code: 2) }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw NSError(domain: "PrivateRoomArtwork", code: 2) }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "PrivateRoomArtwork", code: 2) }
    return data as Data
}

for image in images {
    guard let fileName = image["filename"], let dimensions = image["size"], let scaleString = image["scale"], let baseSize = Double(dimensions.split(separator: "x")[0]), let scale = Double(scaleString.replacingOccurrences(of: "x", with: "")) else {
        FileHandle.standardError.write(Data("Invalid icon manifest row: \(image)\n".utf8))
        throw NSError(domain: "PrivateRoomArtwork", code: 3)
    }
    let data = try render(side: Int((baseSize * scale).rounded()))
    try data.write(to: iconDirectory.appendingPathComponent(fileName), options: .atomic)
}
try render(side: 1024).write(to: repository.appendingPathComponent("PrivateChat/Resources/SecureChatDesktopIcon.png"), options: .atomic)
print("PrivateRoom original vector icons rendered for all existing asset slots.")
