// Preserve the artwork while giving it a rounded macOS icon silhouette.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: render-app-icon.swift INPUT.png OUTPUT.png")
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: 1024, height: 1024,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not read the icon or create its drawing context")
}

// Transparent margins match the footprint of neighboring Dock icons.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let outline = CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil)
context.addPath(outline)
context.clip()
context.interpolationQuality = .high
context.draw(image, in: tile)

guard let rendered = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create the rounded icon PNG")
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not save the rounded icon PNG")
}
