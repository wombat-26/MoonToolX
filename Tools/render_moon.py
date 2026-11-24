# Rendert photometrisch korrekte Mondphasen aus der NASA-LROC-Farbkarte (CGI Moon Kit, gemeinfrei).
# Blick vom mittleren Erdpunkt (sel. Breite 0, Länge 0), Norden oben, Osten (Mare Crisium) rechts.
# Bild "moon_EEE": EEE = Elongation Sonne-Mond in Grad (0 = Neumond, 90 = erstes Viertel, 180 = Vollmond).
import numpy as np, sys, os, json
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
tex_path, out_dir = sys.argv[1], sys.argv[2]
OUT = int(sys.argv[3]) if len(sys.argv) > 3 else 600
STEP = int(sys.argv[4]) if len(sys.argv) > 4 else 2
SS = 2
N = OUT * SS
tex = np.asarray(Image.open(tex_path).convert('RGB')).astype(np.float32) / 255.0
lum = tex @ np.array([0.2126, 0.7152, 0.0722], np.float32)
tex = lum[..., None] + 0.45 * (tex - lum[..., None])          # Farbe dezent reduzieren
tex = np.power(tex, 2.2)                                       # linearisieren
H, W, _ = tex.shape

c = (np.arange(N) + 0.5) / N * 2 - 1
x, y = np.meshgrid(c, -c)                                      # y nach oben
r2 = x * x + y * y
disk = r2 <= 1.0
z = np.sqrt(np.clip(1 - r2, 0, 1))
lat = np.arcsin(np.clip(y, -1, 1))
lon = np.arctan2(x, z)
u = (np.degrees(lon) + 180) / 360 * W - 0.5
v = (90 - np.degrees(lat)) / 180 * H - 0.5
u0 = np.floor(u).astype(int); v0 = np.floor(v).astype(int)
fu = (u - u0)[..., None]; fv = (v - v0)[..., None]
u1 = (u0 + 1) % W; u0 %= W
v0c = np.clip(v0, 0, H - 1); v1c = np.clip(v0 + 1, 0, H - 1)
albedo = ((tex[v0c, u0] * (1 - fu) + tex[v0c, u1] * fu) * (1 - fv)
          + (tex[v1c, u0] * (1 - fu) + tex[v1c, u1] * fu) * fv)
albedo[~disk] = 0
mu = z

def lunar_lambert_L(alpha_deg):
    a = alpha_deg
    return float(np.clip(1 - 0.019 * a + 2.42e-4 * a * a - 1.46e-6 * a ** 3, 0, 1))

def render(E):
    Ls = np.radians(180.0 - E)                                  # subsolare selenogr. Länge
    alpha = np.degrees(np.arccos(np.cos(Ls)))                   # Phasenwinkel
    mu0 = z * np.cos(Ls) + x * np.sin(Ls)
    Lf = max(lunar_lambert_L(alpha), 0.8)              # helle Sichelränder wie im Foto
    lit = np.where(mu0 > 0, 2 * Lf * mu0 / np.maximum(mu0 + mu, 1e-6) + (1 - Lf) * mu0, 0.0)
    earth_frac = (1 - np.cos(np.radians(alpha))) / 2           # Erdphase vom Mond aus
    shine = 0.0065 * earth_frac ** 2
    img = albedo * (lit + shine)[..., None]
    return img

full = render(180)
gain = 0.96 / np.percentile(full[disk].max(axis=-1), 99.7)
os.makedirs(out_dir, exist_ok=True)
names = []
for E in range(0, 360, STEP):
    raw = render(E)
    litpix = raw[disk].max(axis=-1)
    p = np.percentile(litpix[litpix > 0.02], 99.0) if (litpix > 0.02).sum() > 200 else 1.0
    g = min(max(gain, 0.96 / max(p * gain, 1e-6) * gain * 0.92), gain * 2.2)   # Belichtung je Phase
    img = np.clip(raw * g, 0, 1) ** (1 / 2.2)
    im = Image.fromarray((img * 255 + 0.5).astype(np.uint8), 'RGB').resize((OUT, OUT), Image.LANCZOS)
    name = f'moon_{E:03d}'
    im.save(os.path.join(out_dir, name + '.jpg'), quality=86, subsampling=0, optimize=True)
    names.append(name)
print('gain', gain, 'images', len(names))
