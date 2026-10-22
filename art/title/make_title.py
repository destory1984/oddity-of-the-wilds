# Pixel title "Oddity of the Wilds": cream letters, gold depth (offset shadow),
# navy outline and one small gold crown over the first O.
# Glyph shapes come from a heavy system font rendered small without anti-aliasing,
# so the result is a fresh drawing in the house style, not a copy of any logo.
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = r"C:\Windows\Fonts\seguibl.ttf"
CREAM, GOLD, NAVY = (248, 240, 224, 255), (232, 176, 24, 255), (24, 48, 112, 255)

def mask_for(text, size):
    f = ImageFont.truetype(FONT, size)
    x0, y0, x1, y1 = f.getbbox(text)
    m = Image.new("L", (x1 - x0 + 4, y1 - y0 + 4), 0)
    ImageDraw.Draw(m).text((2 - x0, 2 - y0), text, font=f, fill=255)
    return m.point(lambda v: 255 if v > 110 else 0), f, x0

def dilate(m, r):
    return m.filter(ImageFilter.MaxFilter(2 * r + 1))

def lettering(text, size, depth=2, outline=2, crown_at=None):
    m, f, x0 = mask_for(text, size)
    pad = depth + outline + 2
    top = 9 if crown_at is not None else 0
    W, H = m.width + pad * 2, m.height + pad * 2 + top
    face = Image.new("L", (W, H), 0); face.paste(m, (pad, pad + top))
    body = face.copy()
    for d in range(1, depth + 1):  # gold depth below and to the right
        sh = Image.new("L", (W, H), 0); sh.paste(m, (pad + d, pad + top + d)); body = Image.composite(sh, body, sh)
    ring = dilate(body, outline)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(NAVY, (0, 0), ring)
    out.paste(GOLD, (0, 0), body)
    out.paste(CREAM, (0, 0), face)
    if crown_at is not None:  # small crown centred over the chosen letter
        cx = pad + (f.getbbox(text[:crown_at])[2] if crown_at else 0) - x0 + (f.getbbox(text[crown_at])[2] - f.getbbox(text[crown_at])[0]) // 2
        cy = pad + top - 2
        crown = [(-5, 0, 11, 3), (-5, -4, 2, 4), (-1, -6, 3, 6), (4, -4, 2, 4)]
        for dx, dy, w, h in crown:
            ImageDraw.Draw(out).rectangle([cx + dx - 1, cy + dy - 1, cx + dx + w, cy + dy + h], fill=NAVY)
        for dx, dy, w, h in crown:
            ImageDraw.Draw(out).rectangle([cx + dx, cy + dy, cx + dx + w - 1, cy + dy + h - 1], fill=GOLD)
        ImageDraw.Draw(out).rectangle([cx, cy + 1, cx, cy + 1], fill=(255, 248, 200, 255))
    return out

big = lettering("Oddity", 40, depth=3, outline=2, crown_at=0)
small = lettering("of the Wilds", 22, depth=2, outline=2)
W = max(big.width, small.width)
img = Image.new("RGBA", (W, big.height + small.height - 4), (0, 0, 0, 0))
img.alpha_composite(big, ((W - big.width) // 2, 0))
img.alpha_composite(small, ((W - small.width) // 2, big.height - 4))
img = img.crop(img.getbbox())
img.save("art/title/title.png")
img.resize((img.width * 4, img.height * 4), Image.NEAREST).save("art/title/title_preview.png")
print(img.size)
