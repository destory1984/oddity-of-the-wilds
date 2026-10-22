# Key out the magenta background of a GPT sprite sheet and repack its grid
# with equal cells, feet on a shared baseline.
# usage: python art/cut.py SRC DST COLS ROWS  (default: the old hero sheet, 4x3)
import sys
from PIL import Image
src, dst, COLS, ROWS = (sys.argv[1:3] + [int(v) for v in sys.argv[3:5]]) if len(sys.argv) > 4 else ('art/hero_sheet.png', 'hero.png', 4, 3)
im = Image.open(src).convert('RGBA')
W, H = im.size
px = im.load()
for y in range(H):
    for x in range(W):
        r, g, b, a = px[x, y]
        if r > 150 and b > 150 and g < 120 and abs(r - b) < 90:
            px[x, y] = (0, 0, 0, 0)
cw, ch = W / COLS, H / ROWS
cells = [im.crop((round(c * cw), round(r * ch), round((c + 1) * cw), round((r + 1) * ch))) for r in range(ROWS) for c in range(COLS)]
boxes = [c.getbbox() for c in cells]
w = max(b[2] - b[0] for b in boxes); h = max(b[3] - b[1] for b in boxes)
CW, CH = w + 8, h + 4
out = Image.new('RGBA', (CW * COLS, CH * ROWS))
for i, (c, b) in enumerate(zip(cells, boxes)):
    part = c.crop(b)
    x = (CW - (b[2] - b[0])) // 2
    out.paste(part, ((i % COLS) * CW + x, (i // COLS) * CH + CH - 2 - part.height))
out.save(dst)
print(out.size, CW, CH)
