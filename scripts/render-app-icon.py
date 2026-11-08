#!/usr/bin/env python3
"""Builds Yeti's app icon: "The bubble" (concept 2 in docs/design/yeti-icon/yeti-icon-concepts.html).

A clear blister bubble fills the tile; sealed inside is the playing-row sticker (a sale-yellow
stock disc with four night-ink bars stepping 100/75/50/25); one thin foil-pink glint rides the
rim; all on night navy.

Writes, under --out (default: the repo root):

  AppleNugs/AppIcon.icon/            the shipping icon, an Icon Composer document. actool compiles
    icon.json                        it for both targets (ASSETCATALOG_COMPILER_APPICON_NAME:
    Assets/*.svg                     AppIcon) into the Liquid Glass icon stack for iOS/macOS 26+
                                     (default, dark, clear, tinted) plus a flat AppIcon.icns /
                                     AppIcon60x60@2x.png for older systems.
  docs/design/yeti-icon/
    yeti-icon-master.svg             the flat 1024 art exactly as picked (painted glare included)
    yeti-icon-small.svg              the hand-tuned small-size version (no flange or glare, heavier
                                     rim, bigger sticker, wider bars) -- reference only, see below
    yeti-icon-dark.svg               the dark appearance as designed (system dark backing)
    yeti-icon-tinted.svg             the tinted appearance, approximated from luminance

Then, unless --no-previews, renders the real system look of the .icon with Icon Composer's own
`ictool` into --previews (default: build/app-icon-previews): every iOS rendition at 1024/180,
macOS at 1024/512/256/128/64/32/16, and a contact sheet.

Why the layers differ from the flat master: iOS 26 / macOS 26 light the icon themselves (specular
edge, glass, group shadows). So the .icon leaves out the painted hot spot, glare streaks, and the
blurred drop shadows -- painting them too would light the plastic twice -- and the night field is
the document's fill so the dark/clear/tinted appearances can replace it.

Why the small master doesn't ship: actool silently prefers a .icon over a same-named appiconset
(verified: identical output bytes with or without the appiconset beside it), and a .icon has no
per-size art, so the system draws 16/32 from these same layers. The layers are tuned to survive
that (no hairlines, a rim heavy enough to hold at 16).

Usage:  python3 scripts/render-app-icon.py [--out DIR] [--previews DIR] [--no-previews]
Needs only python3 and Xcode (for ictool / sips). No third-party packages.
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys

# ---------------------------------------------------------------- tokens (Yeti theme)
NIGHT, SNOW, FOIL, SALE, INK = "#0F1424", "#E9EEF7", "#FF8FC4", "#F2E27A", "#0F1424"
STOCK = ("#FBF1A6", SALE, "#E3D267")          # sale-yellow stock disc, light to edge
NIGHT_TOP, NIGHT_BOTTOM = "#151C33", "#0B0F1C"  # the field's vertical gradient ends
INTERIOR = "#1C2648"                           # the air inside the bubble

# ---------------------------------------------------------------- geometry (1024 canvas)
BX, BY, BW, BH, BR = 112, 116, 800, 800, 214   # the bubble
FLANGE = 36                                    # heat-sealed lip around it
SX, SY, SR, SROT = 512, 524, 262, -9           # the sticker: center, radius, tilt (degrees)
RIM = 7                                        # concept rim width


def rrect(x, y, w, h, r, extra=""):
    return f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{r:g}" {extra}/>'


def svg(body, defs=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            + (f"<defs>{defs}</defs>" if defs else "") + body + "</svg>\n")


def stair_rects(cx, cy, d, bw=0.10, gap=0.07, H=0.46):
    """Four bars stepping down 100/75/50/25 (the row sticker's figure). Returns (x, y, w, h, r)."""
    bw, gap, H = d * bw, d * gap, d * H
    total = 4 * bw + 3 * gap
    x0, base = cx - total / 2, cy + H / 2
    return [(x0 + i * (bw + gap), base - H * f, bw, H * f, d * 0.012) for i, f in enumerate((1, .75, .5, .25))]


def bars(cx, cy, d, color=INK, **kw):
    return "".join(rrect(round(x, 1), round(y, 1), round(w, 1), round(h, 1), round(r, 1), f'fill="{color}"')
                   for x, y, w, h, r in stair_rects(cx, cy, d, **kw))


def foil_glint_path(x, y, r):
    """The one foil glint: rides the rim around the bubble's top-left corner."""
    k = 0.5523
    return (f"M{x} {y + r * 1.55:.0f} L{x} {y + r:.0f} C{x} {y + r * (1 - k):.0f} {x + r * (1 - k):.0f} {y} "
            f"{x + r:.0f} {y} L{x + r * 1.55:.0f} {y}")


def stock_gradient(gid):
    return (f'<radialGradient id="{gid}" cx=".34" cy=".30" r=".78">'
            f'<stop offset="0" stop-color="{STOCK[0]}"/><stop offset=".55" stop-color="{STOCK[1]}"/>'
            f'<stop offset="1" stop-color="{STOCK[2]}"/></radialGradient>')


FILM = ('<linearGradient id="film" x1="0" y1="0" x2="1" y2="1">'
        '<stop offset="0" stop-color="#E1E9FA" stop-opacity=".22"/><stop offset=".42" stop-color="#E1E9FA" stop-opacity=".04"/>'
        '<stop offset="1" stop-color="#E1E9FA" stop-opacity=".10"/></linearGradient>')
SHADE = ('<radialGradient id="shade" cx=".92" cy=".95" r=".7">'
         '<stop offset="0" stop-color="#040710" stop-opacity=".5"/><stop offset="1" stop-color="#040710" stop-opacity="0"/></radialGradient>')
RIMTOP = ('<linearGradient id="rimtop" x1="0" y1="0" x2="0" y2="1">'
          '<stop offset="0" stop-color="#FFFFFF" stop-opacity=".42"/><stop offset=".22" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>')
GLOW = ('<radialGradient id="glow" cx=".5" cy="-.1" r=".8">'
        f'<stop offset="0" stop-color="{SNOW}" stop-opacity=".16"/><stop offset="1" stop-color="{SNOW}" stop-opacity="0"/></radialGradient>')
NIGHTG = ('<linearGradient id="night" x1="0" y1="0" x2="0" y2="1">'
          f'<stop offset="0" stop-color="{NIGHT_TOP}"/><stop offset=".6" stop-color="{NIGHT}"/>'
          f'<stop offset="1" stop-color="{NIGHT_BOTTOM}"/></linearGradient>')


# ---------------------------------------------------------------- flat masters (docs)
def flat_master(field_fill='url(#night)', extra_defs=NIGHTG, glow=True):
    """Concept 2 exactly as it appears on the concepts page (lifted from its generator)."""
    defs = (extra_defs + GLOW + FILM + SHADE + RIMTOP + stock_gradient("stock")
            + '<radialGradient id="hot"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".5"/>'
              '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>'
            + '<filter id="blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="22"/></filter>'
            + '<filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="9"/></filter>'
            + f'<clipPath id="clip">{rrect(BX, BY, BW, BH, BR)}</clipPath>')
    x, y, w, h, r, f = BX, BY, BW, BH, BR, FLANGE
    hx, hy = x + w * 0.30, y + h * 0.17
    cx, cy, d = x + w / 2, y + h / 2, max(w, h) * 1.6
    b = [f'<rect width="1024" height="1024" fill="{field_fill}"/>']
    if glow:
        b.append('<rect width="1024" height="1024" fill="url(#glow)"/>')
    b += [
        rrect(x + 6, y + 30, w, h, r, 'fill="#03060D" opacity=".6" filter="url(#blur)"'),
        rrect(x - f, y - f, w + 2 * f, h + 2 * f, r + f,
              f'fill="{SNOW}" fill-opacity=".045" stroke="{SNOW}" stroke-opacity=".17" stroke-width="5"'),
        '<g clip-path="url(#clip)">',
        rrect(x, y, w, h, r, f'fill="{INTERIOR}"'),
        f'<g transform="rotate({SROT} {SX} {SY})">',
        f'<circle cx="{SX + 3}" cy="{SY + SR * 0.09:.0f}" r="{SR}" fill="#000" opacity=".45" filter="url(#soft)"/>',
        f'<circle cx="{SX}" cy="{SY}" r="{SR}" fill="url(#stock)"/>',
        bars(SX, SY, 2 * SR),
        '</g>',
        rrect(x, y, w, h, r, 'fill="url(#film)"'),
        rrect(x, y, w, h, r, 'fill="url(#shade)"'),
        f'<ellipse cx="{hx:.0f}" cy="{hy:.0f}" rx="{w * 0.25:.0f}" ry="{h * 0.10:.0f}" '
        f'transform="rotate(-20 {hx:.0f} {hy:.0f})" fill="url(#hot)"/>',
        f'<g transform="rotate(28 {cx:.0f} {cy:.0f})">'
        f'<rect x="{cx + w * 0.16:.0f}" y="{cy - d / 2:.0f}" width="{w * 0.045:.0f}" height="{d:.0f}" fill="#FFFFFF" opacity=".15"/>'
        f'<rect x="{cx + w * 0.27:.0f}" y="{cy - d / 2:.0f}" width="{w * 0.026:.0f}" height="{d:.0f}" fill="#FFFFFF" opacity=".07"/></g>',
        '</g>',
        rrect(x, y, w, h, r, f'fill="none" stroke="{SNOW}" stroke-opacity=".40" stroke-width="{RIM}"'),
        rrect(x + 7, y + 7, w - 14, h - 14, r - 7, 'fill="none" stroke="url(#rimtop)" stroke-width="6"'),
        f'<path d="{foil_glint_path(x, y, r)}" fill="none" stroke="{FOIL}" stroke-width="9" stroke-linecap="round"/>',
    ]
    return svg("".join(b), defs)


def small_master():
    """The hand-tuned small size from the concepts page ("My pick" panel)."""
    sr, sx, sy = 336, 512, 512
    return svg(
        f'<rect width="1024" height="1024" fill="{NIGHT}"/>'
        + rrect(92, 92, 840, 840, 230, f'fill="{INTERIOR}"')
        + f'<g transform="rotate({SROT} {sx} {sy})"><circle cx="{sx}" cy="{sy}" r="{sr}" fill="url(#stock)"/>'
        + bars(sx, sy, 2 * sr, bw=0.13, gap=0.06, H=0.48) + '</g>'
        + rrect(92, 92, 840, 840, 230, f'fill="none" stroke="{SNOW}" stroke-opacity=".62" stroke-width="34"'),
        stock_gradient("stock"))


def tinted_master():
    """Tinted mode, approximated: luminance mapped onto a warm user tint (as on the concepts page)."""
    body = flat_master()
    inner = body[body.index(">", body.index("<svg")) + 1: body.rindex("</svg>")]
    return svg(f'<g filter="url(#tint)">{inner}</g>',
               '<filter id="tint" color-interpolation-filters="sRGB">'
               '<feColorMatrix type="matrix" values=".2126 .7152 .0722 0 0  .2126 .7152 .0722 0 0  .2126 .7152 .0722 0 0  0 0 0 1 0"/>'
               '<feComponentTransfer><feFuncR type="table" tableValues="0.05 1.00"/>'
               '<feFuncG type="table" tableValues="0.04 0.78"/><feFuncB type="table" tableValues="0.03 0.46"/>'
               '</feComponentTransfer></filter>')


# ---------------------------------------------------------------- .icon layers
# Plain shapes, flat or gradient fills, no filters or clip paths: the system draws the shadows and
# the glass. Every layer is the full 1024 canvas, so no layer needs a position offset.
def layer_glow():
    return svg('<rect width="1024" height="1024" fill="url(#glow)"/>', GLOW)


def layer_flange():
    x, y, w, h, r, f = BX, BY, BW, BH, BR, FLANGE
    return svg(rrect(x - f, y - f, w + 2 * f, h + 2 * f, r + f,
                     f'fill="{SNOW}" fill-opacity=".045" stroke="{SNOW}" stroke-opacity=".17" stroke-width="5"'))


def layer_interior():
    return svg(rrect(BX, BY, BW, BH, BR, f'fill="{INTERIOR}"'))


def layer_disc():
    return svg(f'<circle cx="{SX}" cy="{SY}" r="{SR}" fill="url(#stock)" transform="rotate({SROT} {SX} {SY})"/>',
               stock_gradient("stock"))


def layer_bars():
    return svg(f'<g transform="rotate({SROT} {SX} {SY})">{bars(SX, SY, 2 * SR)}</g>')


def layer_film():
    x, y, w, h, r = BX, BY, BW, BH, BR
    return svg(rrect(x, y, w, h, r, 'fill="url(#film)"') + rrect(x, y, w, h, r, 'fill="url(#shade)"'), FILM + SHADE)


def layer_rim():
    x, y, w, h, r = BX, BY, BW, BH, BR
    return svg(rrect(x, y, w, h, r, f'fill="none" stroke="{SNOW}" stroke-opacity=".40" stroke-width="{RIM}"')
               + rrect(x + 7, y + 7, w - 14, h - 14, r - 7, 'fill="none" stroke="url(#rimtop)" stroke-width="6"'),
               RIMTOP)


def layer_foil():
    return svg(f'<path d="{foil_glint_path(BX, BY, BR)}" fill="none" stroke="{FOIL}" stroke-width="9" stroke-linecap="round"/>')


LAYERS = {
    "glow.svg": layer_glow, "flange.svg": layer_flange, "interior.svg": layer_interior,
    "disc.svg": layer_disc, "bars.svg": layer_bars,
    "film.svg": layer_film, "rim.svg": layer_rim, "foil.svg": layer_foil,
}


def srgb(hex_color, alpha=1.0):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"


def layer(name, image, glass=False, **extra):
    d = {"name": name, "image-name": image, "glass": glass, "hidden": False}
    d.update(extra)
    return d


def group(name, layers, shadow=("neutral", 0.5), specular=True, translucency=None):
    g = {"name": name, "layers": layers,
         "shadow": {"kind": shadow[0], "opacity": shadow[1]},
         "specular": specular,
         "translucency": {"enabled": translucency is not None, "value": translucency or 0.5}}
    return g


def icon_json():
    """Groups are listed FRONT FIRST (the JSON's z-order), layers likewise within a group."""
    return {
        # Night field. Dark lets the system's own dark backing show (the art is already night);
        # tinted/clear are drawn by the system from luminance.
        "fill": {"linear-gradient": [srgb(NIGHT_TOP), srgb(NIGHT_BOTTOM)]},
        "fill-specializations": [
            {"value": {"linear-gradient": [srgb(NIGHT_TOP), srgb(NIGHT_BOTTOM)]}},
            {"appearance": "dark", "value": "automatic"},
        ],
        "groups": [
            # The glint gets its own group with no specular: inside the Bubble group the glass
            # rim's highlight flecked it white where the two overlap.
            group("Foil", [layer("Foil glint", "foil.svg")], shadow=("none", 0.5), specular=False),
            # The rim is real Liquid Glass (a lit bevel), which is what replaces the painted
            # hot spot and glare streaks of the flat master.
            group("Bubble", [
                layer("Rim", "rim.svg", glass=True),
                layer("Film", "film.svg"),
            ], shadow=("none", 0.5), specular=True),
            group("Sticker", [
                layer("Bars", "bars.svg"),
                layer("Disc", "disc.svg",
                      **{"fill-specializations": [{"appearance": "tinted",
                                                   "value": {"solid": "srgb:1.00000,1.00000,1.00000,1.00000"}}]}),
            ], shadow=("neutral", 0.5), specular=False),
            group("Card", [
                layer("Interior", "interior.svg"),
                layer("Flange", "flange.svg"),
                layer("Glow", "glow.svg",
                      **{"hidden-specializations": [{"appearance": "dark", "value": True},
                                                    {"appearance": "tinted", "value": True}]}),
            ], shadow=("neutral", 0.6), specular=False),
        ],
        "supported-platforms": {"squares": "shared"},
    }


# ---------------------------------------------------------------- previews
def _developer_dir():
    try:
        return subprocess.run(["xcode-select", "-p"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "/Applications/Xcode.app/Contents/Developer"


# Icon Composer ships inside the selected Xcode (…/Xcode.app/Contents/Applications).
ICTOOL = os.path.join(os.path.dirname(_developer_dir()), "Applications", "Icon Composer.app",
                      "Contents", "Executables", "ictool")


def ictool(doc, out, platform, rendition, px):
    subprocess.run([ICTOOL, doc, "--export-image", "--output-file", out, "--platform", platform,
                    "--rendition", rendition, "--width", str(px), "--height", str(px), "--scale", "1"],
                   check=True, stdout=subprocess.DEVNULL)


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=here)
    ap.add_argument("--previews", default=os.path.join(here, "build", "app-icon-previews"))
    ap.add_argument("--no-previews", action="store_true")
    a = ap.parse_args()

    icon = os.path.join(a.out, "AppleNugs", "AppIcon.icon")
    assets = os.path.join(icon, "Assets")
    if os.path.isdir(assets):
        shutil.rmtree(assets)
    os.makedirs(assets)
    for name, fn in LAYERS.items():
        with open(os.path.join(assets, name), "w") as fh:
            fh.write(fn())
    with open(os.path.join(icon, "icon.json"), "w") as fh:
        json.dump(icon_json(), fh, indent=2, sort_keys=True)
        fh.write("\n")
    print("wrote", icon)

    docs = os.path.join(a.out, "docs", "design", "yeti-icon")
    os.makedirs(docs, exist_ok=True)
    masters = {
        "yeti-icon-master.svg": flat_master(),
        "yeti-icon-small.svg": small_master(),
        "yeti-icon-dark.svg": flat_master(field_fill="url(#sys)", glow=False, extra_defs=(
            '<linearGradient id="sys" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2C2C30"/>'
            '<stop offset="1" stop-color="#0B0B0D"/></linearGradient>')),
        "yeti-icon-tinted.svg": tinted_master(),
    }
    for name, text in masters.items():
        with open(os.path.join(docs, name), "w") as fh:
            fh.write(text)
    print("wrote", ", ".join(masters), "in", docs)

    if a.no_previews:
        return
    if not os.path.exists(ICTOOL):
        sys.exit(f"error: ictool not found at {ICTOOL} (Xcode 26+ ships it inside Icon Composer.app)")
    p = a.previews
    os.makedirs(p, exist_ok=True)
    for rendition in ("Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"):
        for px in (1024, 180):
            ictool(icon, os.path.join(p, f"ios-{rendition}-{px}.png"), "iOS", rendition, px)
    for px in (1024, 512, 256, 128, 64, 32, 16):
        ictool(icon, os.path.join(p, f"macos-Default-{px}.png"), "macOS", "Default", px)
    for px in (64, 32, 16):
        ictool(icon, os.path.join(p, f"ios-Default-{px}.png"), "iOS", "Default", px)
    print("previews in", p)


if __name__ == "__main__":
    main()
