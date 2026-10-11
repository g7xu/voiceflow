import CoreGraphics

// The ContextInbox app icon: one silhouette that is a sheet of paper on top and a map pin below.
// `variant` is the 1024 master; `variantSmall` is a hand-tuned rendition for 64 px and below.

struct DocPinGeometry {
    var left: CGFloat = 282, right: CGFloat = 742, top: CGFloat = 846
    var fold: CGFloat = 146
    // A near-square top-left corner: a round one beside the cut top-right corner reads as a shield.
    var corner: CGFloat = 32
    var knee: CGFloat = 380              // y of the virtual corner where each straight side meets its diagonal
    var kneeRadius: CGFloat = 170
    var tip = CGPoint(x: 512, y: 150)
    var tipRadius: CGFloat = 20
    var foldJoint: CGFloat = 14
    var flapRadius: CGFloat = 22
}

func docPinOutline(_ g: DocPinGeometry) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: g.tip.x, y: g.top))
    p.addArc(tangent1End: CGPoint(x: g.right - g.fold, y: g.top), tangent2End: CGPoint(x: g.right, y: g.top - g.fold), radius: g.foldJoint)
    p.addArc(tangent1End: CGPoint(x: g.right, y: g.top - g.fold), tangent2End: CGPoint(x: g.right, y: g.knee), radius: g.foldJoint)
    p.addArc(tangent1End: CGPoint(x: g.right, y: g.knee), tangent2End: g.tip, radius: g.kneeRadius)
    p.addArc(tangent1End: g.tip, tangent2End: CGPoint(x: g.left, y: g.knee), radius: g.tipRadius)
    p.addArc(tangent1End: CGPoint(x: g.left, y: g.knee), tangent2End: CGPoint(x: g.left, y: g.top), radius: g.kneeRadius)
    p.addArc(tangent1End: CGPoint(x: g.left, y: g.top), tangent2End: CGPoint(x: g.tip.x, y: g.top), radius: g.corner)
    p.closeSubpath()
    return p
}

/// The folded-over back of the paper: the lower-left half of the fold square. It overshoots the
/// outline on its two outer sides and is meant to be drawn clipped to `docPinOutline`.
func docPinFlap(_ g: DocPinGeometry) -> CGPath {
    let r = g.flapRadius
    let p = CGMutablePath()
    p.move(to: CGPoint(x: g.right - g.fold, y: g.top + 4))
    p.addLine(to: CGPoint(x: g.right - g.fold, y: g.top - g.fold + r))
    p.addQuadCurve(to: CGPoint(x: g.right - g.fold + r, y: g.top - g.fold), control: CGPoint(x: g.right - g.fold, y: g.top - g.fold))
    p.addLine(to: CGPoint(x: g.right + 4, y: g.top - g.fold))
    p.closeSubpath()
    return p
}

/// The flap's pixels that lie wholly inside it, as a staircase; the half-covered pixels on the fold
/// line keep the blue-on-background blend, which draws the fold as a mid-blue edge.
func docPinFlapStairs(_ g: DocPinGeometry, unit: CGFloat) -> CGPath {
    let n = Int((g.fold / unit).rounded())
    let p = CGMutablePath()
    for i in 0..<max(n - 1, 0) {
        let rows = CGFloat(n - 1 - i)
        p.addRect(CGRect(x: g.right - g.fold + CGFloat(i) * unit, y: g.top - g.fold, width: unit, height: rows * unit))
    }
    return p
}

func docPinDisc(_ c: CGPoint, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
}

/// Small-size proportions, in canvas units before pixel snapping.
struct DocPinSmallSpec {
    var left: CGFloat = 256, right: CGFloat = 768, top: CGFloat = 832
    var fold: CGFloat = 192
    var knee: CGFloat = 400, kneeRadius: CGFloat = 128
    var tipY: CGFloat = 128, tipRadius: CGFloat = 12, corner: CGFloat = 32
    var dotY: CGFloat = 512, dotR: CGFloat = 112
    var body: (UInt32, UInt32) = (0x4F80FF, 0x2B4FE0)
    var flap: UInt32 = 0xC8D7FF
    var flapStairs = false                             // fill only the pixels wholly inside the flap
    var crease: UInt32? = 0x2B4AD0
    var creaseOffset = CGSize(width: -1, height: -1)   // in device pixels
    var creaseFade: CGFloat = 0.2                      // crease alpha at the far ends of the L
}

/// Hand-tuned per pixel size, like Apple's separate 16/32/64 artwork. Odd body widths are centred on
/// a pixel column so the pin ends in a one-pixel tip, and at least one body-coloured pixel row
/// separates the dot from the flap and its crease.
func docPinSmallSpec(pixels: CGFloat) -> DocPinSmallSpec {
    var s = DocPinSmallSpec()
    if pixels <= 24 {
        // 16 px: body columns 5-11, fold 3 px. The dot is centred on a pixel and wider than 3 px:
        // an exact 3 px disc renders as a plus sign. A crease here would merge with the dot.
        s.left = 320; s.right = 768; s.top = 832; s.fold = 192
        s.dotR = 120; s.dotY = 480
        s.knee = 360; s.kneeRadius = 96
        s.flap = 0xD0DCFF; s.flapStairs = true; s.crease = nil
    } else if pixels <= 48 {
        // 32 px: body 13 px wide and 17 rows tall before the taper, so the page reads as portrait
        // paper; at 15 px wide the page is as wide as it is tall and reads as a badge. Fold 5 px,
        // dot 6 px with one blue row between it and the crease.
        s.left = 320; s.right = 736; s.top = 864; s.fold = 160
        s.dotR = 96; s.dotY = 544
        s.knee = 336; s.kneeRadius = 140
    } else {
        // 64 px: the master's proportions, body 28 px wide, fold 10 px, dot 13 px.
        s.left = 288; s.right = 736; s.top = 848; s.fold = 160
        s.dotR = 106; s.dotY = 556
        s.tipY = 160; s.knee = 384; s.kneeRadius = 170; s.tipRadius = 16
    }
    return s
}

func docPinDrawSmall(_ ctx: CGContext, _ s: DocPinSmallSpec) {
    background(ctx, top: 0xF5F7FF, bottom: 0xD9DEF2)
    let unit = 1 / ctx.userSpaceToDeviceSpaceTransform.a     // canvas units per device pixel
    func snap(_ v: CGFloat) -> CGFloat { (v / unit).rounded() * unit }

    var g = DocPinGeometry()
    g.left = snap(s.left); g.right = snap(s.right); g.top = snap(s.top)
    g.fold = snap(s.fold)
    g.knee = s.knee; g.kneeRadius = s.kneeRadius
    g.tip = CGPoint(x: (g.left + g.right) / 2, y: s.tipY)
    g.tipRadius = s.tipRadius
    g.corner = s.corner
    g.foldJoint = 0
    g.flapRadius = 0
    let outline = docPinOutline(g)

    fillGradient(ctx, outline, rgb(s.body.0), rgb(s.body.1), CGPoint(x: 512, y: g.top), CGPoint(x: 512, y: g.tip.y))
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()
    // A hard-edged stand-in for the master's soft flap shadow: an L along the flap's two free edges,
    // darkest at their right-angle corner and fading toward the outline, as a fold shadow does.
    if let crease = s.crease {
        let corner = CGPoint(x: g.right - g.fold + s.creaseOffset.width * unit, y: g.top - g.fold + s.creaseOffset.height * unit)
        ctx.saveGState()
        ctx.translateBy(x: s.creaseOffset.width * unit, y: s.creaseOffset.height * unit)
        ctx.addPath(docPinFlap(g))
        ctx.restoreGState()
        ctx.saveGState()
        ctx.clip()
        let fade = CGGradient(colorsSpace: srgb, colors: [rgb(crease), rgb(crease, s.creaseFade)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(fade, startCenter: corner, startRadius: 0, endCenter: corner, endRadius: g.fold, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }
    fill(ctx, s.flapStairs ? docPinFlapStairs(g, unit: unit) : docPinFlap(g), rgb(s.flap))
    ctx.restoreGState()

    fill(ctx, docPinDisc(CGPoint(x: g.tip.x, y: s.dotY), s.dotR), rgb(0xFFFFFF))
}

let variantSmall: ((CGContext) -> Void)? = { ctx in
    docPinDrawSmall(ctx, docPinSmallSpec(pixels: canvas * ctx.userSpaceToDeviceSpaceTransform.a))
}

let variant: (CGContext) -> Void = { ctx in
    background(ctx, top: 0xF5F7FF, bottom: 0xD9DEF2)
    let g = DocPinGeometry()
    let outline = docPinOutline(g)

    withShadow(ctx, y: -14, blur: 30, alpha: 0.30) { fill(ctx, outline, rgb(0x4C7DFF)) }
    fillGradient(ctx, outline, rgb(0x5A88FF), rgb(0x2346D6), CGPoint(x: 512, y: g.top), CGPoint(x: 512, y: g.tip.y))
    fillGradient(ctx, outline, rgb(0xFFFFFF, 0.12), rgb(0xFFFFFF, 0), CGPoint(x: 512, y: g.top), CGPoint(x: 512, y: g.top - 240))

    // Clipping the flap to the outline keeps its edges on the rounded fold joints.
    ctx.saveGState()
    ctx.addPath(outline)
    ctx.clip()
    let flap = docPinFlap(g)
    withShadow(ctx, y: -10, blur: 12, alpha: 0.32) { fill(ctx, flap, rgb(0xA4BCFF)) }
    fillGradient(ctx, flap, rgb(0xC6D6FF), rgb(0x90ABFF), CGPoint(x: g.right - g.fold, y: g.top), CGPoint(x: g.right, y: g.top - g.fold))
    ctx.restoreGState()

    let c = CGPoint(x: 512, y: 580), r: CGFloat = 112
    let dot = docPinDisc(c, r)
    withShadow(ctx, y: -8, blur: 18, alpha: 0.25) { fill(ctx, dot, rgb(0xFFFFFF)) }
    fillGradient(ctx, dot, rgb(0xFFFFFF), rgb(0xE4EAFB), CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x, y: c.y - r))
}
