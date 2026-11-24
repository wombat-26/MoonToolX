import json, os, shutil, sys
from PIL import Image, ImageDraw, ImageFilter
root = sys.argv[1]; imgs = sys.argv[2]
def wjson(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f: json.dump(obj, f, indent=2)
info = {"info": {"author": "xcode", "version": 1}}

# Mondphasen (Shared)
cat = os.path.join(root, 'Shared/MoonImages.xcassets'); wjson(os.path.join(cat, 'Contents.json'), info)
for fn in sorted(os.listdir(imgs)):
    name = fn[:-4]; d = os.path.join(cat, name + '.imageset'); os.makedirs(d, exist_ok=True)
    shutil.copy(os.path.join(imgs, fn), d)
    wjson(os.path.join(d, 'Contents.json'), {"images": [{"filename": fn, "idiom": "universal"}], **info})

# App-Katalog
app = os.path.join(root, 'App/Assets.xcassets'); wjson(os.path.join(app, 'Contents.json'), info)
wjson(os.path.join(app, 'AccentColor.colorset/Contents.json'), {"colors": [{"color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": "0.980", "green": "0.890", "blue": "0.620"}}, "idiom": "universal"}], **info})

# App-Icon: macOS-Raster 1024, Inhalt 824 mit Eckradius 185
S = 1024; icon = Image.new('RGBA', (S, S), (0, 0, 0, 0))
mask = Image.new('L', (S, S), 0); ImageDraw.Draw(mask).rounded_rectangle((100, 100, 924, 924), radius=185, fill=255)
bg = Image.new('RGBA', (S, S))
top, bot = (22, 30, 70), (4, 6, 18)
for y in range(S):
    t = y / S; bg.paste(tuple(int(top[i] * (1 - t) + bot[i] * t) for i in range(3)) + (255,), (0, y, S, y + 1))
import random; random.seed(7); d = ImageDraw.Draw(bg)
for _ in range(90):
    x, y, r = random.uniform(110, 914), random.uniform(110, 914), random.uniform(1, 3)
    d.ellipse((x, y, x + r, y + r), fill=(255, 255, 255, random.randint(60, 190)))
moon = Image.open(os.path.join(imgs, 'moon_130.jpg')).convert('RGB').resize((620, 620), Image.LANCZOS)
mm = Image.new('L', (620, 620), 0); ImageDraw.Draw(mm).ellipse((0, 0, 619, 619), fill=255)
glow = Image.new('RGBA', (S, S), (0, 0, 0, 0)); ImageDraw.Draw(glow).ellipse((190, 190, 834, 834), fill=(200, 215, 255, 110))
glow = glow.filter(ImageFilter.GaussianBlur(40))
bg = Image.alpha_composite(bg, glow); bg.paste(moon, (202, 202), mm)
shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0)); shadow.paste((0, 0, 0, 120), (0, 0), mask.filter(ImageFilter.GaussianBlur(14)).point(lambda v: v))
shadow = shadow.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -12))
icon = Image.alpha_composite(icon, shadow); icon.paste(bg, (0, 0), mask)
iconset = os.path.join(app, 'AppIcon.appiconset'); os.makedirs(iconset, exist_ok=True)
entries = []
for pt in (16, 32, 128, 256, 512):
    for sc in (1, 2):
        px = pt * sc; fn = f'icon_{pt}x{pt}@{sc}x.png'
        icon.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, fn))
        entries.append({"filename": fn, "idiom": "mac", "scale": f"{sc}x", "size": f"{pt}x{pt}"})
wjson(os.path.join(iconset, 'Contents.json'), {"images": entries, **info})
icon.save('/tmp/icon_preview.png')
print('ok')
