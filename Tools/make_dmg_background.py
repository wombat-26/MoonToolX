# Hintergrund für das DMG-Fenster (640 × 400 pt, @1x und @2x)
import math, random, sys, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont
FONT = sys.argv[1]; out = sys.argv[2]
W, H = 640, 460   # 400 pt Inhalt + Reserve, falls der Finder keine Pfad-/Statusleiste zeigt
APP, DEST, ICON_Y = (170, 200), (470, 200), 200

def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try: f.set_variation_by_axes([14 if size < 20 else 28, weight])   # opsz, wght
    except Exception: pass
    return f

def render(s):
    w, h = W * s, H * s
    img = Image.new('RGBA', (w, h))
    top, bot = (28, 32, 80), (5, 6, 18)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h; d.line([(0, y), (w, y)], fill=tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,))
    # sanftes Leuchten hinter dem Pfeil
    glow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((150 * s, 90 * s, 490 * s, 310 * s), fill=(120, 140, 255, 55))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(60 * s)))
    d = ImageDraw.Draw(img)
    random.seed(7)
    keep_clear = [(40, 265, 600, 305)]   # Finder-Beschriftungen
    for _ in range(170):
        x, y = random.uniform(0, W), random.uniform(0, H)
        if any(math.hypot(x - cx, y - cy) < 80 for cx, cy in (APP, DEST)): continue
        if any(x0 <= x <= x1 and y0 <= y <= y1 for x0, y0, x1, y1 in keep_clear): continue
        r = random.choice([0.5, 0.7, 0.9, 1.2]) * s
        d.ellipse((x * s - r, y * s - r, x * s + r, y * s + r), fill=(255, 255, 255, random.randint(70, 200)))
    # Kein Text im Bild: Ein DMG kann die Sprache nicht wechseln. Pfeil und Finder-Beschriftungen
    # („MoonToolX“, „Applications“ in Systemsprache) erklären die Installation sprachneutral.
    # Pfeil (Bogen, Cyan → Violett) mit Leuchten
    def bez(t):
        p0, p1, p2 = (262, ICON_Y + 6), (320, ICON_Y - 34), (378, ICON_Y + 6)
        return ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
    def color(t):
        return (int(130 + 60 * t), int(228 - 100 * t), 255, 255)
    arrow = Image.new('RGBA', (w, h), (0, 0, 0, 0)); ad = ImageDraw.Draw(arrow)
    N = 200; lw = 5 * s
    for i in range(N):
        t = i / (N - 1) * 0.9
        x, y = bez(t); ad.ellipse((x * s - lw / 2, y * s - lw / 2, x * s + lw / 2, y * s + lw / 2), fill=color(t))
    # Pfeilspitze in Bahnrichtung
    tx, ty = bez(1.0); bx, by = bez(0.88)
    ang = math.atan2(ty - by, tx - bx); L, Wd = 20, 11
    tip = (tx * s, ty * s)
    left = ((tx - L * math.cos(ang) + Wd * math.sin(ang)) * s, (ty - L * math.sin(ang) - Wd * math.cos(ang)) * s)
    right = ((tx - L * math.cos(ang) - Wd * math.sin(ang)) * s, (ty - L * math.sin(ang) + Wd * math.cos(ang)) * s)
    ad.polygon([tip, left, right], fill=color(1.0))
    img = Image.alpha_composite(img, arrow.filter(ImageFilter.GaussianBlur(7 * s)))
    img = Image.alpha_composite(img, arrow)
    d = ImageDraw.Draw(img)
    # halbhelle Unterlagen für die Finder-Beschriftungen (lesbar mit schwarzer und weißer Schrift)
    for cx, _ in (APP, DEST):
        # Finder (macOS 27) setzt die Beschriftung bei 128-pt-Symbolen mit Mitte bei ≈ 283,5 pt (Symbolmitte 200 pt)
        d.rounded_rectangle(((cx - 76) * s, 273.5 * s, (cx + 76) * s, 293.5 * s), radius=10 * s, fill=(120, 126, 150, 255))
    return img.convert('RGB')

os.makedirs(out, exist_ok=True)
render(1).save(os.path.join(out, 'background.png'))
render(2).save(os.path.join(out, 'background@2x.png'))
print('ok')
