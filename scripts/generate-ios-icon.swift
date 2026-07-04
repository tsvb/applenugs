// Regenerates the full-bleed iOS app icon
// (AppleNugs/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png).
//
// iOS icons are full-bleed and opaque — the system applies its own squircle
// mask, so unlike the Mac icon there are no built-in rounded corners or
// transparent margins. This redraws the SAME waveform mark as the Mac master
// (its 11-bar symmetric envelope was measured from icon_512x512@2x.png) on a
// full-canvas graphite gradient with a warm depth glow, so the two icons stay
// a matched pair.
//
//   swift scripts/generate-ios-icon.swift \
//     AppleNugs/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png
//
// Run with no argument to preview into /tmp.
import AppKit

let size = 1024
let canvas = CGFloat(size)
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon_ios_1024.png"

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("ctx") }

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
func rgba(_ hex: UInt32, _ a: CGFloat) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let sp = CGColorSpace(name: CGColorSpace.sRGB)!

// CoreGraphics origin is bottom-left; the mark is vertically symmetric so the
// waveform is orientation-agnostic, while the background gradient runs top→bottom.

// 1) Background: full-canvas graphite gradient, a shade deeper than the Mac
//    squircle so it reads as premium at full bleed (iOS applies its own mask).
let bg = CGGradient(colorsSpace: sp,
    colors: [rgb(0x322F2A), rgb(0x201E1A), rgb(0x121110)] as CFArray,
    locations: [0.0, 0.55, 1.0])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: canvas), end: CGPoint(x: 0, y: 0), options: [])

// 2) Soft warm glow behind the waveform for depth.
let glow = CGGradient(colorsSpace: sp,
    colors: [rgba(0xFF8C16, 0.16), rgba(0xFF8C16, 0.0)] as CFArray,
    locations: [0.0, 1.0])!
ctx.drawRadialGradient(glow,
    startCenter: CGPoint(x: canvas * 0.5, y: canvas * 0.5), startRadius: 0,
    endCenter: CGPoint(x: canvas * 0.5, y: canvas * 0.5), endRadius: canvas * 0.42,
    options: [])

// 3) The waveform mark — the exact 11-bar symmetric envelope recovered from the
//    Mac master, uniformly scaled up (S) to fill the full-bleed canvas while
//    keeping the same visual proportion the mark has inside the Mac squircle.
//    Bars are one clip path filled by a single vertical gradient, so short
//    center bars catch only the middle band of the amber→orange ramp — as in
//    the master.
let heights: [CGFloat] = [0.1475, 0.2568, 0.3682, 0.4561, 0.3076, 0.1982,
                          0.3076, 0.4561, 0.3682, 0.2568, 0.1475]
let firstX: CGFloat = 0.2388, lastX: CGFloat = 0.7603
let barW: CGFloat = 0.0258
let S: CGFloat = 1.24   // full-bleed upscale about the center
let cx0 = canvas * 0.5, cy0 = canvas * 0.5

let barPath = CGMutablePath()
let n = heights.count
var tallest: CGFloat = 0
for (i, h) in heights.enumerated() {
    let xNorm = firstX + (lastX - firstX) * CGFloat(i) / CGFloat(n - 1)
    let xc = cx0 + (xNorm - 0.5) * canvas * S
    let w = barW * canvas * S
    let barH = h * canvas * S
    tallest = max(tallest, barH)
    let rect = CGRect(x: xc - w / 2, y: cy0 - barH / 2, width: w, height: barH)
    barPath.addRoundedRect(in: rect, cornerWidth: w / 2, cornerHeight: w / 2)
}

ctx.saveGState()
ctx.addPath(barPath)
ctx.clip()
let barGrad = CGGradient(colorsSpace: sp,
    colors: [rgb(0xFFA533), rgb(0xFF8C16), rgb(0xFF7200)] as CFArray,
    locations: [0.0, 0.5, 1.0])!
// Gradient spans the tallest bar's extent (top = high y).
ctx.drawLinearGradient(barGrad,
    start: CGPoint(x: 0, y: cy0 + tallest / 2),
    end: CGPoint(x: 0, y: cy0 - tallest / 2), options: [])
ctx.restoreGState()

guard let out = ctx.makeImage() else { fatalError("makeImage") }
let rep = NSBitmapImageRep(cgImage: out)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
