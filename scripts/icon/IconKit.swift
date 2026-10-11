import CoreGraphics

// Drawing helpers for the app icon, on Apple's 1024 macOS icon grid (824 pt body, 100 pt margin).

let canvas: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func context(_ pixels: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, _ from: CGPoint, _ to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: srgb, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// Offset and blur are in canvas units. Core Graphics applies shadow parameters in device pixels,
/// ignoring the CTM, so they're scaled here; otherwise a 32 px render gets a 1024 px-sized shadow.
func withShadow(_ ctx: CGContext, y: CGFloat, blur: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    let scale = ctx.userSpaceToDeviceSpaceTransform.a
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: y * scale), blur: blur * scale, color: rgb(0x000000, alpha))
    draw()
    ctx.restoreGState()
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

func background(_ ctx: CGContext, top: UInt32, bottom: UInt32) {
    withShadow(ctx, y: -10, blur: 24, alpha: 0.30) {
        ctx.addPath(bodyPath)
        ctx.setFillColor(rgb(bottom))
        ctx.fillPath()
    }
    fillGradient(ctx, bodyPath, rgb(top), rgb(bottom), CGPoint(x: 512, y: 924), CGPoint(x: 512, y: 100))
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.addPath(CGPath(ellipseIn: CGRect(x: -150, y: 600, width: 1324, height: 640), transform: nil))
    ctx.setFillColor(rgb(0xFFFFFF, 0.07))
    ctx.fillPath()
    ctx.restoreGState()
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}
