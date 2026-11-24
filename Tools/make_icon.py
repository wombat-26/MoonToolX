# Ebenen für ein Liquid-Glass-App-Icon (Icon Composer .icon, macOS 26/27)
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
out = sys.argv[1]; moon_src = sys.argv[2]
A = os.path.join(out, 'Assets'); os.makedirs(A, exist_ok=True)
S = 1024; C = S / 2

# 1) Sterne (ohne Glas)
st = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(st); random.seed(11)
for _ in range(120):
    x, y = random.uniform(40, 984), random.uniform(40, 984)
    if math.hypot(x - C, y - C) < 330: continue
    r = random.choice([1.2, 1.6, 2.2, 2.8, 3.6])
    d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, random.randint(110, 235)))
for (x, y, r) in [(205, 215, 15), (835, 300, 11), (770, 845, 9)]:   # Funkelsterne
    for ang in (0, 90):
        L = r * 3.2; w = r * 0.32
        poly = [(x - L, y), (x - w, y - w), (x, y - L), (x + w, y - w), (x + L, y), (x + w, y + w), (x, y + L), (x - w, y + w)]
        d.polygon(poly, fill=(255, 250, 235, 230))
st = st.filter(ImageFilter.GaussianBlur(0.6)); st.save(os.path.join(A, 'stars.png'))

# 2) Mond als Kugel (Glas): Foto aus der LROC-Karte, zunehmender Mond
R = 300
m = Image.open(moon_src).convert('RGB').resize((2 * R, 2 * R), Image.LANCZOS)
mask = Image.new('L', (8 * R, 8 * R), 0); ImageDraw.Draw(mask).ellipse((4, 4, 8 * R - 4, 8 * R - 4), fill=255)
mask = mask.resize((2 * R, 2 * R), Image.LANCZOS)
arr = np.asarray(m).astype(np.float32)
# Nachtseite leicht bläulich anheben, damit die Glaskugel ganz sichtbar bleibt
yy, xx = np.mgrid[0:2 * R, 0:2 * R]; rr = np.hypot(xx - R + .5, yy - R + .5) / R
lum = arr.mean(axis=2, keepdims=True)
night = np.clip(1 - lum / 40, 0, 1)
tint = np.array([28, 36, 70], np.float32) * (0.55 + 0.45 * rr[..., None])
arr = arr + night * tint
moon = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)); moon.putalpha(mask)
layer = Image.new('RGBA', (S, S), (0, 0, 0, 0)); layer.paste(moon, (int(C - R), int(C - R)), moon)
layer.save(os.path.join(A, 'moon.png'))

# 3) Umlaufbahn: gekippte Ellipse, hinten und vorne getrennt
a, b, rot, thick = 455, 128, math.radians(-18), 30
def ring(front):
    im = Image.new('RGBA', (S * 2, S * 2), (0, 0, 0, 0)); dr = ImageDraw.Draw(im)
    N = 720
    for i in range(N):
        t = 2 * math.pi * i / N
        is_front = math.sin(t) > 0
        if is_front != front: continue
        x, y = a * math.cos(t), b * math.sin(t)
        X = C + x * math.cos(rot) - y * math.sin(rot); Y = C + x * math.sin(rot) + y * math.cos(rot)
        k = (math.cos(t) + 1) / 2                                    # Farbverlauf Cyan → Violett
        col = (int(120 + 70 * (1 - k)), int(225 - 95 * (1 - k)), 255, 255)
        w = thick * (1.0 if front else 0.78)
        dr.ellipse((2 * (X - w / 2), 2 * (Y - w / 2), 2 * (X + w / 2), 2 * (Y + w / 2)), fill=col)
    return im.resize((S, S), Image.LANCZOS)
back = ring(False)
# hinterer Teil der Bahn nur außerhalb der Mondscheibe sichtbar: eine Ebene, Schnitt exakt am Mondrand
disc = Image.new('L', (4 * S, 4 * S), 0)
ImageDraw.Draw(disc).ellipse((4 * (C - R), 4 * (C - R), 4 * (C + R), 4 * (C + R)), fill=255)
disc = disc.resize((S, S), Image.LANCZOS)
ba = np.asarray(back).copy(); ba[..., 3] = (ba[..., 3].astype(np.float32) * (1 - np.asarray(disc) / 255)).astype(np.uint8)
front = Image.alpha_composite(Image.fromarray(ba, 'RGBA'), ring(True))
# Erde als kleine Kugel vorne auf der Bahn
t = math.radians(118); x, y = a * math.cos(t), b * math.sin(t)
ex = C + x * math.cos(rot) - y * math.sin(rot); ey = C + x * math.sin(rot) + y * math.cos(rot)
er = 56
yy, xx = np.mgrid[0:2 * er, 0:2 * er].astype(np.float32)
dx, dy = (xx - er + .5) / er, (yy - er + .5) / er
rr = np.hypot(dx, dy)
hl = np.clip(1 - np.hypot(dx + 0.38, dy + 0.42) / 1.1, 0, 1)          # Lichtpunkt oben links
base = np.stack([30 + 60 * hl, 110 + 110 * hl, 235 + 20 * hl], -1)
base *= (0.75 + 0.25 * np.sqrt(np.clip(1 - rr * rr, 0, 1)))[..., None]   # Randabdunklung
alpha = np.clip((1 - rr) * er * 1.5, 0, 1) * 255
e = Image.fromarray(np.dstack([np.clip(base, 0, 255), alpha]).astype(np.uint8), 'RGBA')
front.paste(e, (int(ex - er), int(ey - er)), e)
front.save(os.path.join(A, 'orbit.png'))

icon = {
  "color-space-for-untagged-svg-colors": "display-p3",
  "fill": {"linear-gradient": ["display-p3:0.16078,0.17647,0.45490,1.00000", "display-p3:0.01961,0.02353,0.08627,1.00000"],
           "orientation": {"start": {"x": 0.5, "y": 0.0}, "stop": {"x": 0.5, "y": 0.85}}},
  "groups": [
    {"name": "Bahn", "layers": [{"image-name": "orbit.png", "name": "orbit", "glass": True}],
     "shadow": {"kind": "layer-color", "opacity": 0.6}, "translucency": {"enabled": True, "value": 0.25}, "specular": True},
    {"name": "Mond", "layers": [{"image-name": "moon.png", "name": "moon", "glass": True}],
     "shadow": {"kind": "neutral", "opacity": 0.55}, "translucency": {"enabled": True, "value": 0.12}, "specular": True},
    {"name": "Sterne", "layers": [{"image-name": "stars.png", "name": "stars", "glass": False}],
     "shadow": {"kind": "none", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.5}},
  ],
  "supported-platforms": {"squares": "shared"}
}
with open(os.path.join(out, 'icon.json'), 'w') as f: json.dump(icon, f, indent=2)
print('ok')
