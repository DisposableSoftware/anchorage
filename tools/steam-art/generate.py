"""Draw Anchorage's app icons and Steam library artwork as SVG (INT-27, INT-42).

Run through scripts/render-steam-art.sh, which also renders the PNGs. By hand:

    nix-shell tools/steam-art/shell.nix --run 'python3 tools/steam-art/generate.py .'

The argument is the repository root. It writes:

    data/steam/portrait.svg  600x900   library capsule (portrait)
    data/steam/wide.svg      920x430   library capsule (wide, "recent games")
    data/steam/hero.svg      1920x620  library hero, no text, lower left kept quiet for the logo
    data/steam/logo.svg      1280x348  the mark and the name, transparent
    data/io.github.DisposableSoftware.Anchorage.svg           app icon ("console tile")
    data/io.github.DisposableSoftware.Anchorage-symbolic.svg  symbolic icon, #2e3436 only
    app/icon.svg             the Godot project icon, the same file as the app icon

The scenes are the "harbour" concept: flat Catppuccin mocha, a night sky over hills and
dark water, and a large mauve anchor breaking the waterline. The anchor is one shape,
`anchor()`, shared by the art and the icons. Text is Inter 800 (app/fonts, OFL 1.1),
shaped with HarfBuzz and converted to paths, so the SVGs need no font to render.

Output is deterministic: random details (stars, waves) come from fixed seeds and numbers
are rounded to two decimals.
"""

import os
import random
import sys

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

APP_ID = "io.github.DisposableSoftware.Anchorage"
NAME = "Anchorage"

# Catppuccin mocha (https://catppuccin.com), the same values as app/src/palette.gd.
C = dict(
    mauve="#cba6f7", text="#cdd6f4", overlay0="#6c7086",
    surface1="#45475a", surface0="#313244", base="#1e1e2e", mantle="#181825",
)
SYMBOLIC = "#2e3436"  # GTK recolours this one colour in symbolic icons
HEADER = "<!-- Drawn by tools/steam-art/generate.py: edit that, not this file. -->\n"


def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def svg(w, h, body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{fmt(w)}" height="{fmt(h)}" '
        f'viewBox="0 0 {fmt(w)} {fmt(h)}">\n'
        + HEADER
        + (f"<defs>{defs}</defs>\n" if defs else "")
        + body
        + "</svg>\n"
    )


# ---------------------------------------------------------------- text

class Font:
    def __init__(self, path):
        self.face = hb.Face(hb.Blob.from_file_path(path))
        self.font = hb.Font(self.face)

    def _shape(self, s, wght, opsz):
        self.font.set_variations({"wght": wght, "opsz": opsz})
        buf = hb.Buffer()
        buf.add_str(s)
        buf.guess_segment_properties()
        hb.shape(self.font, buf, {"kern": True, "liga": True})
        return buf.glyph_infos, buf.glyph_positions

    def width(self, s, size, wght=800, opsz=32, track=-0.02):
        _, pos = self._shape(s, wght, opsz)
        upem = self.face.upem
        return (sum(p.x_advance for p in pos) + track * upem * (len(pos) - 1)) * size / upem

    def fit(self, s, max_w, start, wght=800):
        """The largest whole size up to start at which s is at most max_w wide."""
        size = start
        while self.width(s, size, wght) > max_w:
            size -= 1
        return size

    def path(self, s, size, x, y, fill, wght=800, opsz=32, align="start", track=-0.02):
        """s as one <path> of glyph outlines, baseline at y, x at its start/middle/end."""
        infos, pos = self._shape(s, wght, opsz)
        upem = self.face.upem
        sc = size / upem
        w = self.width(s, size, wght, opsz, track)
        x -= {"start": 0, "middle": w / 2, "end": w}[align]
        pen = SVGPathPen(None, ntos=fmt)
        cx = 0
        for info, p in zip(infos, pos):
            t = (sc, 0, 0, -sc, x + (cx + p.x_offset) * sc, y - p.y_offset * sc)
            self.font.draw_glyph_with_pen(info.codepoint, TransformPen(pen, t))
            cx += p.x_advance + track * upem
        return f'<path fill="{fill}" d="{pen.getCommands()}"/>\n'


# ---------------------------------------------------------------- the mark

def anchor(cx, top, h, color, t=11.0, notch=0.3, attrs=""):
    """The anchor: ring, stock, shank, round arms and arrow flukes, from fills only.

    Drawn in a box 100 units tall, centred on cx with its top at top, scaled to h.
    t is the stroke weight in box units (thicker for small sizes); notch lifts the
    back of each fluke so it reads as a barb. Returns a <g> in absolute coordinates.
    """
    s = h / 100.0

    def X(v):
        return fmt(cx + v * s)

    def Y(v):
        return fmt(top + v * s)

    def L(v):
        return fmt(v * s)

    half = t / 2
    ring_r = max(12.0, t * 0.95)
    ring_cy = ring_r + half
    stock_y = ring_cy + ring_r + half + t * 0.9
    arc_r = 36.0
    arc_cy = 100 - arc_r - half
    out = []

    ro, ri = ring_r + half, ring_r - half
    out.append(
        f'<path fill-rule="evenodd" d="M{X(-ro)},{Y(ring_cy)}a{L(ro)},{L(ro)} 0 1,0 {L(2 * ro)},0'
        f'a{L(ro)},{L(ro)} 0 1,0 {L(-2 * ro)},0Z'
        f'M{X(-ri)},{Y(ring_cy)}a{L(ri)},{L(ri)} 0 1,0 {L(2 * ri)},0'
        f'a{L(ri)},{L(ri)} 0 1,0 {L(-2 * ri)},0Z"/>'
    )
    shank_top = ring_cy + ring_r + half - 0.5
    out.append(
        f'<rect x="{X(-half)}" y="{Y(shank_top)}" width="{L(t)}" '
        f'height="{L(arc_cy + arc_r - shank_top)}"/>'
    )
    sw = 17.0
    out.append(
        f'<rect x="{X(-sw - half)}" y="{Y(stock_y - half)}" width="{L(2 * sw + t)}" '
        f'height="{L(t)}" rx="{L(half)}"/>'
    )
    ro, ri = arc_r + half, arc_r - half
    out.append(
        f'<path d="M{X(-ro)},{Y(arc_cy)}A{L(ro)},{L(ro)} 0 0,0 {X(ro)},{Y(arc_cy)}'
        f'L{X(ri)},{Y(arc_cy)}A{L(ri)},{L(ri)} 0 0,1 {X(-ri)},{Y(arc_cy)}Z"/>'
    )
    fw, fl = t * 0.95, t * 1.5
    for mx in (-arc_r, arc_r):
        out.append(
            f'<path d="M{X(mx)},{Y(arc_cy - fl)}L{X(mx + fw)},{Y(arc_cy + t * 0.45)}'
            f'L{X(mx)},{Y(arc_cy + t * (0.45 - notch))}L{X(mx - fw)},{Y(arc_cy + t * 0.45)}Z"/>'
        )
    return f'<g fill="{color}"{attrs}>' + "".join(out) + "</g>\n"


def waterline(top, h):
    """Where the water meets an anchor of height h placed at top: just below the arm
    tips, so the flukes stand in the air and the arms hang in the water."""
    return top + 62 * h / 100


# ---------------------------------------------------------------- the harbour

def overlaps(x0, y0, x1, y1, boxes):
    return any(x0 < bx1 and x1 > bx0 and y0 < by1 and y1 > by0 for bx0, by0, bx1, by1 in boxes)


def stars(x0, x1, y0, y1, seed, n, avoid=()):
    rnd = random.Random(seed)
    out = ""
    for _ in range(n):
        r = rnd.choice((1.2, 1.6, 2.2))
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        if not overlaps(x - r, y - r, x + r, y + r, avoid):
            out += f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r)}"/>'
    return f'<g fill="{C["overlay0"]}">{out}</g>\n'


def waves(x0, x1, y0, y1, seed, n, avoid=()):
    """Short rounded dashes on the water, longer and thicker towards the viewer."""
    rnd = random.Random(seed)
    out = ""
    for _ in range(n):
        y = rnd.uniform(y0, y1)
        depth = (y - y0) / max(1, y1 - y0)
        w = rnd.uniform(20, 70) * (0.6 + depth)
        x = rnd.uniform(x0, x1 - w)
        h = 3 + depth
        if not overlaps(x, y, x + w, y + h, avoid):
            out += (f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" '
                    f'rx="{fmt(h / 2)}"/>')
    return f'<g fill="{C["surface0"]}">{out}</g>\n'


def hills(W, horizon, fill, pts):
    d = f"M0,{fmt(horizon)}" + "".join(f"L{fmt(x)},{fmt(horizon - h)}" for x, h in pts)
    return f'<path {fill} d="{d}L{fmt(W)},{fmt(horizon)}Z"/>\n'


def harbour(W, H, horizon, mark, moon, seed, star_box=None, avoid=(), wave_density=4200):
    """The scene without text: sky, stars, moon, hills, water, the anchor across the
    waterline and the moon's reflection. mark = (cx, top, h); moon = (x, y, r)."""
    sky, water = C["base"], C["mantle"]
    ax, atop, ah = mark
    mx, my, mr = moon
    defs = (
        f'<clipPath id="sky"><rect width="{fmt(W)}" height="{fmt(horizon)}"/></clipPath>'
        f'<clipPath id="sea"><rect y="{fmt(horizon)}" width="{fmt(W)}" '
        f'height="{fmt(H - horizon)}"/></clipPath>'
    )
    sx0, sy0, sx1, sy1 = star_box or (0, 10, W, horizon - 70)
    n_stars = round((sx1 - sx0) * (sy1 - sy0) / 9000)
    body = f'<rect width="{fmt(W)}" height="{fmt(H)}" fill="{sky}"/>\n'
    body += stars(sx0, sx1, sy0, sy1, seed, n_stars, avoid)
    body += f'<circle cx="{fmt(mx)}" cy="{fmt(my)}" r="{fmt(mr)}" fill="{C["surface1"]}"/>\n'
    body += (f'<circle cx="{fmt(mx + mr * 0.38)}" cy="{fmt(my - mr * 0.18)}" '
             f'r="{fmt(mr * 0.86)}" fill="{sky}"/>\n')
    # Palette colours only; the in-between shades are a palette colour at an opacity, as
    # the style guide's state colours are (the near ridge lies wholly on the far one).
    body += hills(W, horizon, f'fill="{C["surface0"]}"', [
        (0, 18), (W * 0.12, 34), (W * 0.22, 20), (W * 0.30, 12), (W * 0.62, 10),
        (W * 0.74, 30), (W * 0.86, 46), (W * 0.95, 26), (W, 22)])
    body += hills(W, horizon, f'fill="{C["base"]}" fill-opacity="0.5"', [
        (0, 6), (W * 0.18, 14), (W * 0.4, 4), (W * 0.7, 6), (W * 0.82, 16), (W, 8)])
    body += f'<rect y="{fmt(horizon)}" width="{fmt(W)}" height="{fmt(H - horizon)}" fill="{water}"/>\n'
    body += waves(0, W, horizon + 14, H - 10, seed + 1, int(W * (H - horizon) / wave_density), avoid)
    body += anchor(ax, atop, ah, C["mauve"], attrs=' clip-path="url(#sky)"')
    # Group opacity, so the overlapping parts of the anchor don't darken each other.
    body += anchor(ax, atop, ah, C["mauve"], attrs=' clip-path="url(#sea)" opacity="0.45"')
    body += f'<rect y="{fmt(horizon - 1.5)}" width="{fmt(W)}" height="3" fill="{C["surface1"]}"/>\n'
    for w, dy in ((mr * 1.6, 12), (mr * 1.1, 26), (mr * 0.6, 40)):
        body += (f'<rect x="{fmt(mx - w / 2)}" y="{fmt(horizon + dy)}" width="{fmt(w)}" '
                 f'height="4" rx="2" fill="{C["surface1"]}"/>\n')
    return defs, body


def portrait(font):
    W, H, mark = 600, 900, (300, 300, 420)
    defs, body = harbour(W, H, waterline(*mark[1:]), mark, moon=(130, 330, 34), seed=11)
    size = font.fit(NAME, 500, 100)
    body += font.path(NAME, size, W / 2, 190, C["text"], align="middle")
    return svg(W, H, body, defs)


def wide(font):
    W, H, mark = 920, 430, (690, 92, 262)
    size = font.fit(NAME, 480, 100)
    name_box = (52, 200 - size * 0.8, 64 + font.width(NAME, size) + 12, 200 + size * 0.25)
    defs, body = harbour(W, H, waterline(*mark[1:]), mark, moon=(520, 64, 26), seed=7,
                         avoid=(name_box,))
    body += font.path(NAME, size, 64, 200, C["text"])
    return svg(W, H, body, defs)


# Steam puts the logo over the hero's lower left by default, so that part stays free of
# detail. Steam crops the hero's sides in narrow windows and keeps a centred safe area,
# so the anchor sits just right of the centre rather than out at the edge.
HERO_QUIET = (0, 170, 940, 620)


def hero():
    W, H, mark = 1920, 620, (1260, 140, 440)
    defs, body = harbour(W, H, waterline(*mark[1:]), mark, moon=(1640, 118, 42), seed=5,
                         avoid=(HERO_QUIET,), wave_density=3600)
    return svg(W, H, body, defs)


def logo(font):
    """The mark and the name side by side on transparency, cropped close."""
    W, pad = 1280, 24
    ah = 300
    aw = ah * 2 * (36 + 11 * 0.95) / 100  # out to the fluke tips
    gap = 56
    size = font.fit(NAME, W - 2 * pad - aw - gap, 260)
    H = ah + 2 * pad
    body = anchor(pad + aw / 2, pad, ah, C["mauve"])
    # Cap height of Inter is about 0.727 em; centre the capitals on the mark.
    base = H / 2 + size * 0.727 / 2
    body += font.path(NAME, size, pad + aw + gap, base, C["text"])
    return svg(W, H, body)


# ---------------------------------------------------------------- icons

def app_icon():
    """The "console tile": a mauve disc with a base-coloured anchor on a surface1 tile."""
    body = (
        f'<rect x="14" y="14" width="100" height="100" rx="18" fill="{C["surface1"]}"/>\n'
        f'<circle cx="64" cy="64" r="40" fill="{C["mauve"]}"/>\n'
        + anchor(64, 35, 58, C["base"], t=16)
    )
    return svg(128, 128, body)


def symbolic_icon():
    """The anchor on its own, redrawn on the 16 px grid so it stays crisp there."""
    f = SYMBOLIC
    body = (
        # ring
        f'<path fill="{f}" fill-rule="evenodd" d="M8 0.5a2.5 2.5 0 1 1 0 5a2.5 2.5 0 1 1 0-5z'
        f'M8 2a1 1 0 1 0 0 2a1 1 0 1 0 0-2z"/>\n'
        # stock and shank
        f'<rect fill="{f}" x="5" y="6" width="6" height="2" rx="1"/>\n'
        f'<rect fill="{f}" x="7" y="5" width="2" height="9"/>\n'
        # arms: a 2 px half ring around (8, 9)
        f'<path fill="{f}" d="M2 9a6 6 0 0 0 12 0h-2a4 4 0 0 1-8 0z"/>\n'
        # flukes
        f'<path fill="{f}" d="M3 5.5l2.5 4.5h-5z"/>\n'
        f'<path fill="{f}" d="M13 5.5l2.5 4.5h-5z"/>\n'
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">\n'
        + HEADER + body + "</svg>\n"
    )


def main(root):
    font = Font(os.path.join(root, "app/fonts/InterVariable.ttf"))
    files = {
        "data/steam/portrait.svg": portrait(font),
        "data/steam/wide.svg": wide(font),
        "data/steam/hero.svg": hero(),
        "data/steam/logo.svg": logo(font),
        f"data/{APP_ID}.svg": app_icon(),
        f"data/{APP_ID}-symbolic.svg": symbolic_icon(),
        "app/icon.svg": app_icon(),
    }
    for rel, content in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(content)
        print(rel)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
