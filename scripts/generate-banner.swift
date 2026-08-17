#!/usr/bin/env swift
//
// generate-banner.swift — draws the README banner and the repo social-preview card.
//
// Output:
//   docs/images/banner-dark.svg    1676x420 (4:1), for prefers-color-scheme: dark
//   docs/images/banner-light.svg   1676x420 (4:1), the <picture> fallback
//   docs/images/social-preview.png 1280x640 (2:1), uploaded by hand in repo settings
//
// Why the lettering is outlined rather than set in <text>:
// GitHub serves repository files from raw.githubusercontent.com under
//     content-security-policy: default-src 'none'; style-src 'unsafe-inline'; sandbox
// An SVG referenced by <img> therefore cannot fetch a font — not a web font, not
// even a base64 @font-face, because default-src 'none' is the fallback for font-src.
// A <text> element would silently fall back to a system font and the faceplate would
// collapse. So every glyph here is converted to a path via CoreText, and the script
// aborts if the OS substitutes a font for one we asked for.
//
// Run:  swift scripts/generate-banner.swift
//
import Foundation
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

let W = 1676.0, H = 420.0          // banner canvas, 4:1; renders at 838pt in GitHub's column
let plateInset = 8.0
let cornerRadius = 22.0

// VU window
let winX = 52.0, winY = 52.0, winW = 944.0, winH = 316.0

// The needle pivot sits far below the canvas, which is how wide, shallow-arc meters
// on cassette decks actually work — the needle enters from the bottom of the window
// and no pivot is visible. The needle is clipped to the window.
let pivot = CGPoint(x: 524, y: 720)
let rScale = 560.0                 // radius of the scale arc
let rTickIn = 532.0                // major tick inner radius
let rTickInMinor = 544.0
let rBand = 572.0                  // the zone band sits just outside the ticks
let rNumeral = 508.0               // numeral centres
let rNeedleTip = 546.0

// Right-hand panel
let panelX = 1046.0

/// Scale marks: (label, angle in degrees from vertical, positive = clockwise).
/// Compressed at the quiet end and open at the loud end, the way a real VU face reads.
let marks: [(String, Double)] = [
    ("-20", -40), ("-10", -22.5), ("-7", -14), ("-5", -8),
    ("-3", -1), ("-1", 7.5), ("0", 15), ("+1", 24), ("+3", 40),
]
let zeroAngle = 15.0
// Sits in the gap between the -7 and -5 marks. Parking it exactly on a labelled
// mark puts the needle through the numeral and neither one survives.
let needleAngle = -11.0
let maskHeight = 26.0              // bottom mask the needle disappears behind
let scaleStart = -40.0, scaleEnd = 40.0

func pt(_ angleDeg: Double, _ r: Double, from c: CGPoint = pivot) -> CGPoint {
    let a = angleDeg * .pi / 180
    return CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a))
}

// MARK: - Palette

struct Palette {
    let plateHi, plateLo: String       // plate gradient, top to bottom
    let edgeHi, edgeLo: String         // machined top highlight / bottom shadow
    let brush: String                  // brushed-texture stroke colour
    let brushHi, brushLo: Double       // its opacities
    let bezel, bezelHi: String         // window surround
    let field, fieldShade: String      // meter card and its recess shading
    let ink, inkSoft: String           // scale marks, numerals, needle — on the cream card
    let plateMark: String              // marks drawn straight onto the plate, with no card behind
    let band: String                   // the pre-0 portion of the zone band
    let red: String                    // the over-0 portion, and the peak tick
    let wordmark: String
    let lcd: String
    let caption: String
    let screwHi, screwLo, screwSlot: String
    let led: String

    static let dark = Palette(
        plateHi: "#1F1A16", plateLo: "#14110E",
        edgeHi: "#3A332B", edgeLo: "#0A0806",
        brush: "#FFFFFF", brushHi: 0.035, brushLo: 0.018,
        bezel: "#0B0A08", bezelHi: "#332C25",
        field: "#EDE4D3", fieldShade: "#B9AE99",
        ink: "#241C12", inkSoft: "#6E6357",
        plateMark: "#A89B8B",
        band: "#241C12", red: "#FF4D2E",
        wordmark: "#E8A13A", lcd: "#5FB6A6", caption: "#A89B8B",
        screwHi: "#4A4238", screwLo: "#17140F", screwSlot: "#0A0806",
        led: "#E8A13A")

    // Not an inversion. The same unit in a lighter anodised finish, with darker ink,
    // so it reads as hardware sitting on GitHub's white rather than a hole in the page.
    static let light = Palette(
        plateHi: "#E6E0D4", plateLo: "#CBC3B4",
        edgeHi: "#F7F3EA", edgeLo: "#A09786",
        brush: "#000000", brushHi: 0.030, brushLo: 0.015,
        bezel: "#4A4237", bezelHi: "#EFEAE0",
        field: "#F8F2E6", fieldShade: "#C9BEA7",
        ink: "#241C12", inkSoft: "#6E6357",
        plateMark: "#241C12",
        band: "#241C12", red: "#C8341A",
        wordmark: "#A15C0B", lcd: "#1F6F62", caption: "#5C5347",
        screwHi: "#F2EEE5", screwLo: "#9C9382", screwSlot: "#6E6558",
        led: "#C8721A")
}

// MARK: - Glyph outlines

/// Positioned glyph outlines for a string, in CoreGraphics (y-up) space with the
/// baseline at y = 0. Aborts rather than let the OS substitute a different face.
func glyphOutlines(_ text: String, font fontName: String, size: Double,
                   tracking: Double = 0) -> (paths: [CGPath], width: Double) {
    let font = CTFontCreateWithName(fontName as CFString, size, nil)
    let actual = CTFontCopyPostScriptName(font) as String
    guard actual.caseInsensitiveCompare(fontName) == .orderedSame else {
        FileHandle.standardError.write(
            "font substituted: asked for \(fontName), got \(actual) — refusing to outline the wrong face\n"
                .data(using: .utf8)!)
        exit(3)
    }
    var attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font
    ]
    if tracking != 0 {
        attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
    }
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attrs))

    var paths: [CGPath] = []
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        guard n > 0 else { continue }
        var glyphs = [CGGlyph](repeating: 0, count: n)
        var pos = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
        CTRunGetPositions(run, CFRangeMake(0, 0), &pos)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
        for i in 0..<n {
            guard let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
            var t = CGAffineTransform(translationX: pos[i].x, y: pos[i].y)
            if let placed = g.copy(using: &t) { paths.append(placed) }
        }
    }
    var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &a, &d, &l)
    return (paths, width)
}

func num(_ v: Double) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r)) : String(format: "%g", r)
}

/// SVG path data for a string, flipped into SVG's y-down space, baseline at y = 0.
func svgTextPath(_ text: String, font: String, size: Double, tracking: Double = 0)
    -> (d: String, width: Double) {
    let (paths, width) = glyphOutlines(text, font: font, size: size, tracking: tracking)
    var d = ""
    for p in paths {
        var flip = CGAffineTransform(scaleX: 1, y: -1)
        guard let f = p.copy(using: &flip) else { continue }
        f.applyWithBlock { e in
            let q = e.pointee.points
            switch e.pointee.type {
            case .moveToPoint:        d += "M\(num(q[0].x)) \(num(q[0].y))"
            case .addLineToPoint:     d += "L\(num(q[0].x)) \(num(q[0].y))"
            case .addQuadCurveToPoint:d += "Q\(num(q[0].x)) \(num(q[0].y)) \(num(q[1].x)) \(num(q[1].y))"
            case .addCurveToPoint:    d += "C\(num(q[0].x)) \(num(q[0].y)) \(num(q[1].x)) \(num(q[1].y)) \(num(q[2].x)) \(num(q[2].y))"
            case .closeSubpath:       d += "Z"
            @unknown default:         break
            }
        }
    }
    return (d, width)
}

// Typefaces. Condensed grotesque for the wordmark and scale, mono for the readout.
let fWordmark = "AvenirNextCondensed-Heavy"
let fScale    = "AvenirNextCondensed-Bold"
let fMono     = "Menlo-Bold"

// MARK: - SVG

func arcPath(from a1: Double, to a2: Double, r: Double) -> String {
    let p1 = pt(a1, r), p2 = pt(a2, r)
    let large = abs(a2 - a1) > 180 ? 1 : 0
    let sweep = a2 > a1 ? 1 : 0     // SVG y-down: increasing angle is a clockwise sweep
    return "M\(num(p1.x)) \(num(p1.y))A\(num(r)) \(num(r)) 0 \(large) \(sweep) \(num(p2.x)) \(num(p2.y))"
}

func svg(_ p: Palette, variant: String) -> String {
    var s = ""
    s += #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \#(num(W)) \#(num(H))" width="\#(num(W))" height="\#(num(H))" role="img" aria-label="AppleNugs">"#
    s += "<title>AppleNugs</title>"

    // ---- defs
    s += "<defs>"
    s += #"<linearGradient id="plate" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\#(p.plateHi)"/><stop offset="1" stop-color="\#(p.plateLo)"/></linearGradient>"#
    // Brushed finish: a tiled pattern rather than several hundred individual strokes,
    // which keeps the file in the low tens of kilobytes.
    s += #"<pattern id="brush" width="7" height="6" patternUnits="userSpaceOnUse"><rect x="0" y="0" width="1" height="6" fill="\#(p.brush)" opacity="\#(num(p.brushHi))"/><rect x="3" y="0" width="1" height="6" fill="\#(p.brush)" opacity="\#(num(p.brushLo))"/><rect x="5.5" y="0" width="0.5" height="6" fill="\#(p.brush)" opacity="\#(num(p.brushLo))"/></pattern>"#
    s += #"<linearGradient id="recess" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="\#(p.fieldShade)" stop-opacity="0.55"/><stop offset="0.22" stop-color="\#(p.fieldShade)" stop-opacity="0.10"/><stop offset="0.8" stop-color="\#(p.fieldShade)" stop-opacity="0"/><stop offset="1" stop-color="\#(p.fieldShade)" stop-opacity="0.28"/></linearGradient>"#
    s += #"<radialGradient id="screw" cx="0.35" cy="0.3" r="0.8"><stop offset="0" stop-color="\#(p.screwHi)"/><stop offset="1" stop-color="\#(p.screwLo)"/></radialGradient>"#
    s += #"<radialGradient id="ledGlow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="\#(p.led)" stop-opacity="0.75"/><stop offset="1" stop-color="\#(p.led)" stop-opacity="0"/></radialGradient>"#
    s += #"<clipPath id="win"><rect x="\#(num(winX))" y="\#(num(winY))" width="\#(num(winW))" height="\#(num(winH))" rx="6"/></clipPath>"#
    s += "</defs>"

    // ---- plate
    s += #"<rect x="0" y="0" width="\#(num(W))" height="\#(num(H))" rx="\#(num(cornerRadius))" fill="url(#plate)"/>"#
    s += #"<rect x="0" y="0" width="\#(num(W))" height="\#(num(H))" rx="\#(num(cornerRadius))" fill="url(#brush)"/>"#
    // machined edges
    s += #"<path d="M\#(num(cornerRadius)) 1.5H\#(num(W - cornerRadius))" stroke="\#(p.edgeHi)" stroke-width="2" opacity="0.9" fill="none"/>"#
    s += #"<path d="M\#(num(cornerRadius)) \#(num(H - 1.5))H\#(num(W - cornerRadius))" stroke="\#(p.edgeLo)" stroke-width="3" opacity="0.85" fill="none"/>"#
    s += #"<rect x="0.75" y="0.75" width="\#(num(W - 1.5))" height="\#(num(H - 1.5))" rx="\#(num(cornerRadius))" fill="none" stroke="\#(p.edgeLo)" stroke-width="1.5" opacity="0.6"/>"#

    // ---- window recess
    s += #"<rect x="\#(num(winX - 10))" y="\#(num(winY - 10))" width="\#(num(winW + 20))" height="\#(num(winH + 20))" rx="12" fill="\#(p.bezel)"/>"#
    s += #"<rect x="\#(num(winX - 10))" y="\#(num(winY - 10))" width="\#(num(winW + 20))" height="\#(num(winH + 20))" rx="12" fill="none" stroke="\#(p.bezelHi)" stroke-width="1.5" opacity="0.5"/>"#
    s += #"<rect x="\#(num(winX))" y="\#(num(winY))" width="\#(num(winW))" height="\#(num(winH))" rx="6" fill="\#(p.field)"/>"#

    // ---- meter face, clipped to the window
    s += #"<g clip-path="url(#win)">"#

    // zone band: ink up to 0, red past it
    s += #"<path d="\#(arcPath(from: scaleStart, to: zeroAngle, r: rBand))" fill="none" stroke="\#(p.band)" stroke-width="4" opacity="0.85"/>"#
    s += #"<path d="\#(arcPath(from: zeroAngle, to: scaleEnd, r: rBand))" fill="none" stroke="\#(p.red)" stroke-width="7"/>"#

    // minor ticks between the labelled marks
    for i in 0..<(marks.count - 1) {
        let a0 = marks[i].1, a1 = marks[i + 1].1
        let mid = (a0 + a1) / 2
        let o = pt(mid, rScale), inn = pt(mid, rTickInMinor)
        let col = mid > zeroAngle ? p.red : p.ink
        s += #"<path d="M\#(num(inn.x)) \#(num(inn.y))L\#(num(o.x)) \#(num(o.y))" stroke="\#(col)" stroke-width="2" opacity="0.75"/>"#
    }
    // major ticks + upright numerals
    for (label, angle) in marks {
        let o = pt(angle, rScale), inn = pt(angle, rTickIn)
        let col = angle >= zeroAngle ? p.red : p.ink
        s += #"<path d="M\#(num(inn.x)) \#(num(inn.y))L\#(num(o.x)) \#(num(o.y))" stroke="\#(col)" stroke-width="3.5"/>"#

        let (d, w) = svgTextPath(label, font: fScale, size: 30)
        let c = pt(angle, rNumeral)
        s += #"<path d="\#(d)" fill="\#(col)" transform="translate(\#(num(c.x - w / 2)) \#(num(c.y + 10)))"/>"#
    }

    // needle
    let tip = pt(needleAngle, rNeedleTip)
    let tail = pt(needleAngle, 300)
    let a = needleAngle * .pi / 180
    let nx = cos(a), ny = sin(a)              // perpendicular to the needle
    let halfTail = 5.0, halfTip = 1.6
    s += #"<path d="M\#(num(tail.x + nx * halfTail)) \#(num(tail.y + ny * halfTail))L\#(num(tip.x + nx * halfTip)) \#(num(tip.y + ny * halfTip))L\#(num(tip.x - nx * halfTip)) \#(num(tip.y - ny * halfTip))L\#(num(tail.x - nx * halfTail)) \#(num(tail.y - ny * halfTail))Z" fill="\#(p.ink)"/>"#

    // Bottom mask. A real meter hides the needle's pivot behind one; without it the
    // needle just stops dead at the window edge and reads as a stray diagonal line.
    s += #"<rect x="\#(num(winX))" y="\#(num(winY + winH - maskHeight))" width="\#(num(winW))" height="\#(num(maskHeight))" fill="\#(p.bezel)"/>"#
    s += #"<path d="M\#(num(winX)) \#(num(winY + winH - maskHeight))H\#(num(winX + winW))" stroke="\#(p.bezelHi)" stroke-width="1.5" opacity="0.45" fill="none"/>"#

    // "VU", and the recess shading over the top of everything
    let (vuD, vuW) = svgTextPath("VU", font: fScale, size: 34, tracking: 3)
    s += #"<path d="\#(vuD)" fill="\#(p.inkSoft)" transform="translate(\#(num(winX + winW / 2 - vuW / 2)) \#(num(winY + winH - maskHeight - 14)))"/>"#
    s += #"<rect x="\#(num(winX))" y="\#(num(winY))" width="\#(num(winW))" height="\#(num(winH))" rx="6" fill="url(#recess)"/>"#
    s += "</g>"

    // ---- right panel: wordmark, readout, caption
    let (wmD, wmW) = svgTextPath("APPLENUGS", font: fWordmark, size: 112, tracking: 1.5)
    s += #"<path d="\#(wmD)" fill="\#(p.wordmark)" transform="translate(\#(num(panelX)) 196)"/>"#

    // hairline under the wordmark, ending where the wordmark does
    s += #"<path d="M\#(num(panelX)) 216H\#(num(panelX + wmW))" stroke="\#(p.wordmark)" stroke-width="2" opacity="0.35"/>"#

    let (lcdD, _) = svgTextPath("ALAC 24/96 · LOSSLESS", font: fMono, size: 27)
    s += #"<path d="\#(lcdD)" fill="\#(p.lcd)" transform="translate(\#(num(panelX)) 262)"/>"#

    let (capD, _) = svgTextPath("NATIVE CLIENT FOR NUGS.NET · UNOFFICIAL", font: fScale, size: 25, tracking: 1.2)
    s += #"<path d="\#(capD)" fill="\#(p.caption)" transform="translate(\#(num(panelX)) 300)"/>"#

    // power LED, level with the readout
    s += #"<circle cx="\#(num(panelX + wmW + 26))" cy="255" r="18" fill="url(#ledGlow)"/>"#
    s += #"<circle cx="\#(num(panelX + wmW + 26))" cy="255" r="6" fill="\#(p.led)"/>"#

    // ---- corner screws
    for (sx, sy) in [(26.0, 26.0), (W - 26, 26.0), (26.0, H - 26), (W - 26, H - 26)] {
        s += #"<circle cx="\#(num(sx))" cy="\#(num(sy))" r="11" fill="url(#screw)"/>"#
        s += #"<circle cx="\#(num(sx))" cy="\#(num(sy))" r="11" fill="none" stroke="\#(p.edgeLo)" stroke-width="1" opacity="0.7"/>"#
        s += #"<path d="M\#(num(sx - 6)) \#(num(sy + 3))L\#(num(sx + 6)) \#(num(sy - 3))" stroke="\#(p.screwSlot)" stroke-width="2.5"/>"#
    }

    s += "</svg>\n"
    return s
}

// MARK: - Social preview card (1280x640, drawn directly to a bitmap)

func drawSocial(_ p: Palette, to url: URL) {
    let w = 1280, h = 640
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create bitmap context")
    }
    func color(_ hex: String, _ alpha: Double = 1) -> CGColor {
        var s = hex; s.removeFirst()
        let v = UInt32(s, radix: 16)!
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: CGFloat(alpha))
    }
    // y-up context; draw in a flipped frame so the layout maths matches the SVG
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)

    // plate
    let grad = CGGradient(colorsSpace: cs,
                          colors: [color(p.plateHi), color(p.plateLo)] as CFArray,
                          locations: [0, 1])!
    ctx.saveGState()
    ctx.addRect(CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
    ctx.clip()
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: CGFloat(h)), options: [])
    ctx.restoreGState()

    // brushed texture
    ctx.setLineWidth(1)
    for x in stride(from: 0, to: Double(w), by: 7) {
        ctx.setStrokeColor(color(p.brush, p.brushHi))
        ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: Double(h))); ctx.strokePath()
        ctx.setStrokeColor(color(p.brush, p.brushLo))
        ctx.move(to: CGPoint(x: x + 3, y: 0)); ctx.addLine(to: CGPoint(x: x + 3, y: Double(h))); ctx.strokePath()
    }

    /// Fill a string's outlines with the baseline at (x, y) in the flipped frame.
    func text(_ str: String, _ font: String, _ size: Double, _ hex: String,
              at x: Double, _ y: Double, tracking: Double = 0,
              centered: Bool = false) -> Double {
        let (paths, width) = glyphOutlines(str, font: font, size: size, tracking: tracking)
        let ox = centered ? x - width / 2 : x
        ctx.saveGState()
        ctx.setFillColor(color(hex))
        ctx.translateBy(x: CGFloat(ox), y: CGFloat(y))
        ctx.scaleBy(x: 1, y: -1)          // glyphs are y-up; the frame is flipped
        for path in paths { ctx.addPath(path) }
        ctx.fillPath()
        ctx.restoreGState()
        return width
    }

    // The card must identify itself: X strips the title, and Slack and Discord
    // shrink it to roughly 380px wide, so the name and the pitch live in the art.
    let wmW = text("APPLENUGS", fWordmark, 168, p.wordmark, at: Double(w) / 2, 300, tracking: 2, centered: true)

    ctx.setStrokeColor(color(p.wordmark, 0.35))
    ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: Double(w) / 2 - wmW / 2, y: 330))
    ctx.addLine(to: CGPoint(x: Double(w) / 2 + wmW / 2, y: 330))
    ctx.strokePath()

    _ = text("A NATIVE MAC AND IPHONE CLIENT FOR NUGS.NET", fScale, 42,
             p.caption, at: Double(w) / 2, 396, tracking: 1.5, centered: true)
    _ = text("GAPLESS · LOSSLESS · OFFLINE · FIVE FRONT PANELS", fMono, 27,
             p.lcd, at: Double(w) / 2, 462, centered: true)
    _ = text("UNOFFICIAL", fScale, 24, p.inkSoft, at: Double(w) / 2, 546,
             tracking: 4, centered: true)

    // A slim VU band across the top so the card is recognisably the same object as
    // the banner. These marks sit straight on the plate with no cream card behind
    // them, so they take plateMark — drawing them in `ink` put near-black on
    // near-black and the band vanished entirely.
    let bandY = 150.0
    ctx.setLineCap(.round)
    ctx.setLineWidth(8)
    ctx.setStrokeColor(color(p.plateMark, 0.85))
    ctx.move(to: CGPoint(x: 300, y: bandY)); ctx.addLine(to: CGPoint(x: 830, y: bandY)); ctx.strokePath()
    ctx.setStrokeColor(color(p.red))
    ctx.move(to: CGPoint(x: 830, y: bandY)); ctx.addLine(to: CGPoint(x: 980, y: bandY)); ctx.strokePath()
    ctx.setLineWidth(3)
    ctx.setStrokeColor(color(p.plateMark, 0.7))
    for i in 0...10 {
        let x = 300 + Double(i) * 68
        ctx.move(to: CGPoint(x: x, y: bandY - 20)); ctx.addLine(to: CGPoint(x: x, y: bandY - 6)); ctx.strokePath()
    }

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not encode PNG") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

// MARK: - Write

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outDir = root.appendingPathComponent("docs/images")
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (name, palette) in [("banner-dark.svg", Palette.dark), ("banner-light.svg", Palette.light)] {
    let url = outDir.appendingPathComponent(name)
    try! svg(palette, variant: name).write(to: url, atomically: true, encoding: .utf8)
    let bytes = (try! Data(contentsOf: url)).count
    print("wrote \(url.lastPathComponent) (\(bytes) bytes)")
}

let socialURL = outDir.appendingPathComponent("social-preview.png")
drawSocial(.dark, to: socialURL)
let socialBytes = (try! Data(contentsOf: socialURL)).count
print("wrote social-preview.png (\(socialBytes) bytes, limit 1048576)")
if socialBytes > 1_000_000 { print("WARNING: social preview is close to GitHub's 1MB limit") }
