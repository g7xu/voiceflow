import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders AppIcon.iconset from `variant` (large sizes) and `variantSmall` (64 px and below,
// hand-tuned so the folded corner survives) in Icon.swift. Usage: icon-gen OUT.iconset

func render(_ pixels: Int) -> CGImage {
    let ctx = context(pixels)
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    if pixels <= 64, let small = variantSmall { small(ctx) } else { variant(ctx) }
    return ctx.makeImage()!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
// iconutil's required names: each point size at 1x and 2x.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL,
                                                   UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, render(points * scale), nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("couldn't write \(name)") }
    }
}
print("wrote \(out.path)")
