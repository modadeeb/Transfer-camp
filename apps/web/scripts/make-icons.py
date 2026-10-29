"""Brand mark: the letter ن (from «نقلة») drawn geometrically — forest bowl, brass dot.
Run: python3 scripts/make-icons.py  (writes public/icons/*.png and public/favicon.svg)"""
from PIL import Image, ImageDraw
import os

FOREST, PAPER, BRASS = (36, 63, 53), (247, 246, 241), (182, 138, 71)
OUT = os.path.join(os.path.dirname(__file__), '..', 'public')

def mark(size, bg=FOREST, fg=PAPER, pad=0.0, radius=0.22, transparent=False):
    S = 1024
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if not transparent:
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * radius), fill=bg)
    inner = S * (1 - 2 * pad)
    off = S * pad
    cx, cy = off + inner * 0.5, off + inner * 0.42
    r = inner * 0.32
    ry = inner * 0.26
    w = inner * 0.10
    # bowl: lower half of a wide ellipse, rounded ends
    box = [cx - r, cy - ry, cx + r, cy + ry]
    d.arc(box, start=0, end=180, fill=fg, width=int(w))
    for x in (cx - r + w / 2, cx + r - w / 2):
        d.ellipse([x - w / 2, cy - w / 2, x + w / 2, cy + w / 2], fill=fg)
    # brass dot
    dr = inner * 0.08
    dy = cy + ry * 0.12
    d.ellipse([cx - dr, dy - dr, cx + dr, dy + dr], fill=BRASS)
    return img.resize((size, size), Image.LANCZOS)

icons = os.path.join(OUT, 'icons')
os.makedirs(icons, exist_ok=True)
mark(192).save(os.path.join(icons, 'icon-192.png'))
mark(512).save(os.path.join(icons, 'icon-512.png'))
mark(512, pad=0.12, radius=0).save(os.path.join(icons, 'maskable-512.png'))
mark(180, radius=0).convert('RGB').save(os.path.join(icons, 'apple-touch-icon.png'))
mark(96, transparent=True, fg=(255, 255, 255)).save(os.path.join(icons, 'badge-96.png'))
mark(48).save(os.path.join(OUT, 'favicon-48.png'))

svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
<rect width="100" height="100" rx="22" fill="#243F35"/>
<path d="M18 42 a32 26 0 0 0 64 0" fill="none" stroke="#F7F6F1" stroke-width="10" stroke-linecap="round"/>
<circle cx="50" cy="45" r="8" fill="#B68A47"/>
</svg>'''
open(os.path.join(OUT, 'favicon.svg'), 'w').write(svg)
print('ok')
