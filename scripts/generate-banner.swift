#!/usr/bin/env swift
//
// generate-banner.swift — draws the README banner and the repo social-preview card
// in the Yeti design: a night-blue blister card hung on a peg, the bubble app icon,
// the "Yeti" wordmark in SF Pro Rounded Heavy (the app's own hero face), a foil
// progress rule (foil means time), and a sale-yellow "Lossless" price sticker.
//
// Output:
//   docs/images/banner-dark.svg    1676x420 (4:1), for prefers-color-scheme: dark
//   docs/images/banner-light.svg   1676x420 (4:1), the <picture> fallback
//   docs/images/social-preview.png 1280x640 (2:1), uploaded by hand in repo settings
//                                  (rendered with rsvg-convert: `brew install librsvg`)
//
// Why the lettering is outlined rather than set in <text>:
// GitHub serves repository files from raw.githubusercontent.com under
//     content-security-policy: default-src 'none'; style-src 'unsafe-inline'; sandbox
// so an SVG referenced by <img> cannot fetch a font, not even a base64 @font-face.
// A <text> element would silently fall back to some system font. Every glyph here is
// converted to a path via CoreText, and the script aborts if the OS substitutes a
// font for the rounded face we asked for.
//
// The icon is the app icon's master art (docs/design/yeti-icon/yeti-icon-master.svg),
// embedded with its ids prefixed so they can't collide with the banner's own.
//
// Colors are the `Theme.yeti` palette (Yeti/Theme/Theme.swift) — keep them in step.
//
// Run:  swift scripts/generate-banner.swift
//
import AppKit
import CoreText
import Foundation

// MARK: - Palette (Theme.yeti)

let base = "#0F1424", raised = "#18203A", hairline = "#2E3A5C", cardStock = "#1B2443"
let snow = "#E9EEF7", slush = "#9FABCE", idle = "#8590B0", foil = "#FF8FC4"
let sale = "#F2E27A", saleHighlight = "#FBF1A6", saleEdge = "#E3D267", stickerInk = "#0F1424"

// MARK: - Glyph outlines

/// SF Pro Rounded at `weight`, or abort: a substituted face would ship a banner in
/// the wrong typeface without anyone noticing.
func rounded(_ size: Double, _ weight: NSFont.Weight) -> CTFont {
    let plain = NSFont.systemFont(ofSize: size, weight: weight)
    guard let desc = plain.fontDescriptor.withDesign(.rounded),
          let font = NSFont(descriptor: desc, size: size) else {
        fatalError("SF Pro Rounded is unavailable on this Mac")
    }
    let name = CTFontCopyPostScriptName(font as CTFont) as String
    guard name.lowercased().contains("rounded") else {
        fatalError("asked for SF Pro Rounded, got \(name)")
    }
    return font as CTFont
}

struct Outline {
    let d: String       // SVG path data, origin at the text's left baseline
    let width: Double   // typographic advance
}

/// `text` as one SVG path, baseline at y = 0, extending right from x = 0.
func outline(_ text: String, _ font: CTFont, tracking: Double = 0) -> Outline {
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        let asked = CTFontCopyPostScriptName(font) as String
        let got = CTFontCopyPostScriptName(runFont) as String
        guard asked == got else { fatalError("font substituted for \"\(text)\": \(asked) → \(got)") }
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for i in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
            // CoreText is y-up; SVG is y-down.
            let t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x, ty: positions[i].y)
            path.addPath(glyph, transform: t)
        }
    }
    return Outline(d: svgPath(path), width: CTLineGetTypographicBounds(line, nil, nil, nil))
}

func fmt(_ v: CGFloat) -> String {
    let r = (Double(v) * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r)) : String(r)
}

func svgPath(_ path: CGPath) -> String {
    var d = ""
    path.applyWithBlock { el in
        let p = el.pointee.points
        switch el.pointee.type {
        case .moveToPoint: d += "M\(fmt(p[0].x)) \(fmt(p[0].y))"
        case .addLineToPoint: d += "L\(fmt(p[0].x)) \(fmt(p[0].y))"
        case .addQuadCurveToPoint: d += "Q\(fmt(p[0].x)) \(fmt(p[0].y)) \(fmt(p[1].x)) \(fmt(p[1].y))"
        case .addCurveToPoint:
            d += "C\(fmt(p[0].x)) \(fmt(p[0].y)) \(fmt(p[1].x)) \(fmt(p[1].y)) \(fmt(p[2].x)) \(fmt(p[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

// MARK: - The icon

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconURL = root.appendingPathComponent("docs/design/yeti-icon/yeti-icon-master.svg")
guard let iconSource = try? String(contentsOf: iconURL, encoding: .utf8) else {
    fatalError("run from the repo root: missing \(iconURL.path)")
}

/// The icon's inner markup with every id (and every reference to one) prefixed.
func iconMarkup(prefix: String) -> (viewBox: String, inner: String) {
    guard let open = iconSource.range(of: ">"),
          let close = iconSource.range(of: "</svg>", options: .backwards),
          let vb = iconSource.range(of: #"viewBox="([^"]+)""#, options: .regularExpression)
    else { fatalError("unexpected icon SVG shape") }
    let viewBox = String(iconSource[vb]).replacingOccurrences(of: "viewBox=", with: "")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    var inner = String(iconSource[open.upperBound..<close.lowerBound])
    inner = inner.replacingOccurrences(of: #"id="([^"]+)""#, with: "id=\"\(prefix)$1\"", options: .regularExpression)
    inner = inner.replacingOccurrences(of: #"url\(#([^)]+)\)"#, with: "url(#\(prefix)$1)", options: .regularExpression)
    inner = inner.replacingOccurrences(of: ##"href="#([^"]+)""##, with: "href=\"#\(prefix)$1\"", options: .regularExpression)
    return (viewBox, inner)
}

// MARK: - Drawing

enum Variant { case dark, light }

struct Canvas {
    let w: Double, h: Double
    /// Inset of the card from the canvas edge (room for the light variant's shadow).
    let inset: Double
    let iconSide: Double
    let wordmarkSize: Double
    let taglineSize: Double
}

let bannerCanvas = Canvas(w: 1676, h: 420, inset: 10, iconSide: 288, wordmarkSize: 168, taglineSize: 40)
let socialCanvas = Canvas(w: 1280, h: 640, inset: 0, iconSide: 300, wordmarkSize: 176, taglineSize: 42)

func drawing(_ c: Canvas, _ variant: Variant, social: Bool = false) -> String {
    let card = (x: c.inset, y: c.inset, w: c.w - 2 * c.inset, h: c.h - 2 * c.inset)
    let radius = social ? 0.0 : 28.0

    // Layout: banner = icon left, words right; social = icon left, words right, taller.
    let iconX = card.x + (social ? 96 : 72)
    let iconY = card.y + (card.h - c.iconSide) / 2 + (social ? 10 : 8)
    let textX = iconX + c.iconSide + (social ? 64 : 76)

    let wordFont = rounded(c.wordmarkSize, .heavy)
    let tagFont = rounded(c.taglineSize, .medium)
    let smallFont = rounded(c.taglineSize * 0.62, .semibold)
    let word = outline("Yeti", wordFont, tracking: -2)
    let tagline = outline("an unofficial player for nugs.net", tagFont)
    let platforms = outline("MAC  ·  IPHONE  ·  IPHONE DUO", smallFont, tracking: 3)

    let wordBaseline = iconY + c.iconSide * 0.50
    let tagBaseline = wordBaseline + c.taglineSize * 1.55
    let ruleY = tagBaseline + c.taglineSize * 0.95
    let ruleW = max(tagline.width, 420)
    let platformsBaseline = ruleY + c.taglineSize * 1.45

    // The sale-yellow price sticker on the card's top-right, tilted like it was slapped on.
    let stickerR = social ? 86.0 : 74.0
    let stickerC = (x: card.x + card.w - (social ? 150 : 130), y: card.y + (social ? 150 : card.h / 2 - 6))
    let stickerFont = rounded(stickerR * 0.36, .heavy)
    let stickerWord = outline("Lossless", stickerFont)
    let stickerSub = outline("24/96", rounded(stickerR * 0.27, .bold))

    let icon = iconMarkup(prefix: "icon-")
    let iconRadius = c.iconSide * 0.225

    var s = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(fmt(c.w)) \(fmt(c.h))" width="\(fmt(c.w))" height="\(fmt(c.h))" role="img" aria-label="Yeti — an unofficial player for nugs.net"><title>Yeti — an unofficial player for nugs.net</title>
    <defs>
    <linearGradient id="night" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#151C33"/><stop offset=".6" stop-color="\(base)"/><stop offset="1" stop-color="#0B0F1C"/></linearGradient>
    <radialGradient id="glow" gradientUnits="userSpaceOnUse" cx="\(fmt(card.x + card.w * 0.25))" cy="\(fmt(card.y - card.h * 0.35))" r="\(fmt(max(card.w, card.h) * 0.62))"><stop offset="0" stop-color="\(snow)" stop-opacity=".10"/><stop offset=".55" stop-color="\(snow)" stop-opacity=".03"/><stop offset="1" stop-color="\(snow)" stop-opacity="0"/></radialGradient>
    <radialGradient id="sticker" cx=".38" cy=".32" r=".75"><stop offset="0" stop-color="\(saleHighlight)"/><stop offset=".55" stop-color="\(sale)"/><stop offset="1" stop-color="\(saleEdge)"/></radialGradient>
    <clipPath id="iconclip"><rect x="\(fmt(iconX))" y="\(fmt(iconY))" width="\(fmt(c.iconSide))" height="\(fmt(c.iconSide))" rx="\(fmt(iconRadius))"/></clipPath>
    <filter id="lift" x="-10%" y="-10%" width="120%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-color="#000" flood-opacity=".45"/></filter>
    <filter id="cardshadow" x="-5%" y="-10%" width="110%" height="130%"><feDropShadow dx="0" dy="4" stdDeviation="5" flood-color="#0F1424" flood-opacity=".28"/></filter>
    </defs>
    """

    // The card. Light pages get a soft shadow; dark pages a frost keyline.
    let cardAttrs = variant == .light ? #" filter="url(#cardshadow)""# : ""
    s += """
    <rect x="\(fmt(card.x))" y="\(fmt(card.y))" width="\(fmt(card.w))" height="\(fmt(card.h))" rx="\(fmt(radius))" fill="url(#night)"\(cardAttrs)/>
    <rect x="\(fmt(card.x))" y="\(fmt(card.y))" width="\(fmt(card.w))" height="\(fmt(card.h))" rx="\(fmt(radius))" fill="url(#glow)"/>
    """
    if variant == .dark && !social {
        s += """
        <rect x="\(fmt(card.x + 0.5))" y="\(fmt(card.y + 0.5))" width="\(fmt(card.w - 1))" height="\(fmt(card.h - 1))" rx="\(fmt(radius - 0.5))" fill="none" stroke="\(hairline)" stroke-width="1.5"/>
        """
    }

    // The hang slot punched through the top of the card.
    let slotW = social ? 110.0 : 96.0, slotH = social ? 26.0 : 22.0
    let slotX = card.x + (card.w - slotW) / 2, slotY = card.y + (social ? 26 : 18)
    s += """
    <rect x="\(fmt(slotX))" y="\(fmt(slotY))" width="\(fmt(slotW))" height="\(fmt(slotH))" rx="\(fmt(slotH / 2))" fill="#080B15"/>
    <rect x="\(fmt(slotX))" y="\(fmt(slotY + slotH))" width="\(fmt(slotW))" height="1.5" rx=".75" fill="\(snow)" opacity=".08"/>
    """

    // The icon, lifted off the card.
    s += """
    <g filter="url(#lift)"><g clip-path="url(#iconclip)"><svg x="\(fmt(iconX))" y="\(fmt(iconY))" width="\(fmt(c.iconSide))" height="\(fmt(c.iconSide))" viewBox="\(icon.viewBox)">\(icon.inner)</svg></g></g>
    <rect x="\(fmt(iconX + 0.75))" y="\(fmt(iconY + 0.75))" width="\(fmt(c.iconSide - 1.5))" height="\(fmt(c.iconSide - 1.5))" rx="\(fmt(iconRadius))" fill="none" stroke="\(snow)" stroke-opacity=".12" stroke-width="1.5"/>
    """

    // Words: the wordmark in snow, the tagline in slush, the platforms in idle.
    s += """
    <path transform="translate(\(fmt(textX)) \(fmt(wordBaseline)))" fill="\(snow)" d="\(word.d)"/>
    <path transform="translate(\(fmt(textX + 4)) \(fmt(tagBaseline)))" fill="\(slush)" d="\(tagline.d)"/>
    """

    // The foil rule: time moving, about two-fifths through the set.
    s += """
    <rect x="\(fmt(textX + 4))" y="\(fmt(ruleY))" width="\(fmt(ruleW))" height="6" rx="3" fill="\(hairline)"/>
    <rect x="\(fmt(textX + 4))" y="\(fmt(ruleY))" width="\(fmt(ruleW * 0.4))" height="6" rx="3" fill="\(foil)"/>
    <circle cx="\(fmt(textX + 4 + ruleW * 0.4))" cy="\(fmt(ruleY + 3))" r="9" fill="\(foil)"/>
    <path transform="translate(\(fmt(textX + 4)) \(fmt(platformsBaseline)))" fill="\(idle)" d="\(platforms.d)"/>
    """

    // The price sticker.
    s += """
    <g transform="rotate(-9 \(fmt(stickerC.x)) \(fmt(stickerC.y)))" filter="url(#lift)">
    <circle cx="\(fmt(stickerC.x))" cy="\(fmt(stickerC.y))" r="\(fmt(stickerR))" fill="url(#sticker)"/>
    <circle cx="\(fmt(stickerC.x))" cy="\(fmt(stickerC.y))" r="\(fmt(stickerR - 1))" fill="none" stroke="\(saleEdge)" stroke-width="2"/>
    <path transform="translate(\(fmt(stickerC.x - stickerWord.width / 2)) \(fmt(stickerC.y + stickerR * 0.02)))" fill="\(stickerInk)" d="\(stickerWord.d)"/>
    <path transform="translate(\(fmt(stickerC.x - stickerSub.width / 2)) \(fmt(stickerC.y + stickerR * 0.40)))" fill="\(stickerInk)" fill-opacity=".72" d="\(stickerSub.d)"/>
    </g>
    """

    s += "</svg>\n"
    return s
}

// MARK: - Output

let outDir = root.appendingPathComponent("docs/images")
func write(_ svg: String, _ name: String) -> URL {
    let url = outDir.appendingPathComponent(name)
    try! svg.write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(name) (\(svg.utf8.count) bytes)")
    return url
}

_ = write(drawing(bannerCanvas, .dark), "banner-dark.svg")
_ = write(drawing(bannerCanvas, .light), "banner-light.svg")

// The social card: rasterized from an SVG of its own, then the SVG is removed.
let socialSVG = write(drawing(socialCanvas, .dark, social: true), "social-preview.svg")
let socialPNG = outDir.appendingPathComponent("social-preview.png")
let rsvg = Process()
rsvg.executableURL = URL(fileURLWithPath: "/usr/bin/env")
rsvg.arguments = ["rsvg-convert", "-w", "1280", "-h", "640", "-o", socialPNG.path, socialSVG.path]
do {
    try rsvg.run()
    rsvg.waitUntilExit()
    if rsvg.terminationStatus == 0 {
        let bytes = (try? Data(contentsOf: socialPNG).count) ?? 0
        print("wrote social-preview.png (\(bytes) bytes, GitHub's limit is 1 MB)")
    } else {
        print("rsvg-convert failed; social-preview.png not updated")
    }
} catch {
    print("rsvg-convert not found (brew install librsvg); social-preview.png not updated")
}
try? FileManager.default.removeItem(at: socialSVG)
