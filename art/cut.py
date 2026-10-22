# Key out the magenta background of art/hero_sheet.png and repack the 4x3 grid
# into hero.png with equal cells, feet on a shared baseline.
from PIL import Image
im = Image.open('art/hero_sheet.png').convert('RGBA')
W, H = im.size
px = im.load()
for y in range(H):
    for x in range(W):
        r, g, b, a = px[x, y]
        if r > 150 and b > 150 and g < 120 and abs(r - b) < 90:
            px[x, y] = (0, 0, 0, 0)
cw, ch = W / 4, H / 3
cells = [im.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch))) for r in range(3) for c in range(4)]
boxes = [c.getbbox() for c in cells]
w = max(b[2] - b[0] for b in boxes); h = max(b[3] - b[1] for b in boxes)
CW, CH = w + 8, h + 4
out = Image.new('RGBA', (CW * 4, CH * 3))
for i, (c, b) in enumerate(zip(cells, boxes)):
    part = c.crop(b)
    cx = (b[0] + b[2]) / 2
    x = round(CW / 2 - (cx - b[0])) if False else (CW - (b[2] - b[0])) // 2
    out.paste(part, ((i % 4) * CW + x, (i // 4) * CH + CH - 2 - part.height))
out.save('hero.png')
print(out.size, CW, CH)
