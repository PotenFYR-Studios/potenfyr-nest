#!/usr/bin/env python3
"""Generate docs/og.png (1200x630) for social/SEO previews.

Deterministic brand image: dark bg, brand gradient glows, dot pattern,
gradient title, panel + ecosystem line. Regenerate after rebranding with:
    python3 scripts/generate-og.py
"""

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1200, 630
BG = (13, 15, 22)
VIOLET, PINK, ORANGE = (139, 92, 246), (236, 72, 153), (249, 115, 22)

FIRA_SANS_XB = "/usr/share/fonts/TTF/FiraSans-ExtraBold.ttf"
FIRA_SANS_SB = "/usr/share/fonts/TTF/FiraSans-SemiBold.ttf"
FIRA_CODE = "/usr/share/fonts/TTF/FiraCodeNerdFont-Regular.ttf"
FIRA_CODE_SB = "/usr/share/fonts/TTF/FiraCodeNerdFont-SemiBold.ttf"


def font(path, size):
    return ImageFont.truetype(path, size)


def base_canvas():
    img = Image.new("RGB", (W, H), BG)
    # brand gradient glows
    glow = Image.new("RGB", (W, H), BG)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-320, -260, 520, 380), fill=(52, 34, 92))
    gd.ellipse((520, -200, 1180, 300), fill=(66, 26, 52))
    gd.ellipse((760, 330, 1360, 800), fill=(58, 34, 20))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    img = Image.blend(img, glow, 0.75)
    # dot pattern
    dots = ImageDraw.Draw(img)
    for y in range(40, H, 34):
        for x in range(40, W, 34):
            dots.ellipse((x, y, x + 2, y + 2), fill=(38, 42, 62))
    # top gradient hairline
    line = Image.new("RGB", (W, 6), BG)
    for x in range(W):
        t = x / W
        if t < 0.5:
            a, b, f = VIOLET, PINK, t * 2
        else:
            a, b, f = PINK, ORANGE, (t - 0.5) * 2
        rgb = tuple(int(a[i] + (b[i] - a[i]) * f) for i in range(3))
        for ry in range(6):
            fade = ry / 6
            line.putpixel((x, ry), (int(rgb[0] * (1 - fade)), int(rgb[1] * (1 - fade)), int(rgb[2] * (1 - fade))))
    img.paste(line, (0, 0))
    return img


def gradient_text(img, text, fnt, center_x, y):
    # render text mask, fill with the brand gradient
    tmp = Image.new("L", (W, H), 0)
    ImageDraw.Draw(tmp).text((center_x, y), text, font=fnt, anchor="mm", fill=255)
    grad = Image.new("RGB", (W, H), BG)
    gdr = ImageDraw.Draw(grad)
    bbox = tmp.getbbox()
    if not bbox:
        return img
    x0, x1 = bbox[0], bbox[2]
    for x in range(x0, x1):
        t = (x - x0) / max(1, x1 - x0)
        if t < 0.5:
            a, b, f = VIOLET, PINK, t * 2
        else:
            a, b, f = PINK, ORANGE, (t - 0.5) * 2
        gdr.line([(x, 0), (x, H)], fill=tuple(int(a[i] + (b[i] - a[i]) * f) for i in range(3)))
    img.paste(grad, (0, 0), tmp)
    return img


def main():
    img = base_canvas()
    d = ImageDraw.Draw(img)

    # kicker
    d.text((W / 2, 132), "POTENFYR STUDIOS  ·  EGG CATALOG", font=font(FIRA_CODE_SB, 26),
           anchor="mm", fill=(154, 160, 180))
    # title
    img = gradient_text(img, "PotenFYR Nest", font(FIRA_SANS_XB, 120), W / 2, 268)
    d = ImageDraw.Draw(img)
    # subtitle
    d.text((W / 2, 372), "Every Multi Egg. One Nest.", font=font(FIRA_SANS_SB, 44),
           anchor="mm", fill=(232, 234, 242))
    # ecosystem chips
    chips = [("Databases", VIOLET), ("50+ Languages", PINK), ("Minecraft", ORANGE)]
    fnt_chip = font(FIRA_SANS_SB, 26)
    widths = [d.textlength(t, font=fnt_chip) + 56 for t, _ in chips]
    gap = 22
    total = sum(widths) + gap * (len(chips) - 1)
    x = (W - total) / 2
    for (label, color), w in zip(chips, widths):
        d.rounded_rectangle((x, 442, x + w, 502), radius=30, outline=color, width=3)
        d.text((x + w / 2, 472), label, font=fnt_chip, anchor="mm", fill=(232, 234, 242))
        x += w + gap
    # footer line
    d.text((W / 2, 572), "pterodactyl  ·  pelican  ·  feather  ·  wisp      auto-synced every 30 minutes",
           font=font(FIRA_CODE, 22), anchor="mm", fill=(122, 128, 150))

    img.save("public/og.png", optimize=True)
    print("wrote public/og.png")


if __name__ == "__main__":
    main()
