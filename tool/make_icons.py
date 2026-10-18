"""Launcher icons, splash images and the status-bar icon, from the TGCG seal.

Run from the repository root after changing assets/brand/tgcg_logo.png:

    uv run --no-project --with pillow==11.1.0 python tool/make_icons.py .

It rewrites the Android launcher, round, adaptive-foreground and splash
images, the white status-bar icon (ic_stat_tgcg) and the iPhone app icons
and launch image. A larger logo file gives sharper large icons.
"""

import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

root = pathlib.Path(sys.argv[1])
res = root / "android/app/src/main/res"
seal = Image.open(root / "assets/brand/tgcg_logo.png").convert("RGBA")
seal = seal.crop(seal.getbbox())  # the seal's own circle, no transparent margin

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def placed(canvas: int, share: float, background=None) -> Image.Image:
    """The seal centred on a square canvas, its diameter `share` of the side."""
    image = Image.new("RGBA", (canvas, canvas), background or (0, 0, 0, 0))
    side = round(canvas * share)
    logo = seal.resize((side, side), Image.LANCZOS)
    offset = (canvas - side) // 2
    image.alpha_composite(logo, (offset, offset))
    return image


def save(image: Image.Image, path: pathlib.Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


# Launcher icons for launchers before Android 8 (and as the round icon): the
# seal fills the icon, as the round badge it is.
for name, scale in DENSITIES.items():
    side = round(48 * scale)
    icon = placed(side, 0.94)
    save(icon, res / f"mipmap-{name}/ic_launcher.png")
    save(icon, res / f"mipmap-{name}/ic_launcher_round.png")
    # Adaptive icon foreground (108dp): the seal inside the 66dp safe circle,
    # with a little room so no launcher shape cuts its ring.
    save(placed(round(108 * scale), 0.63), res / f"mipmap-{name}/ic_launcher_foreground.png")
    # Splash logo before Android 12: 144dp in the middle of a white screen.
    save(placed(round(144 * scale), 1.0), res / f"drawable-{name}/splash_logo.png")

# Status-bar icon: white on transparent, as Android draws it. The seal is too
# fine at 24dp, so a ring with TG in it.
font = ImageFont.truetype(sys.argv[2] if len(sys.argv) > 2 else "arialbd.ttf", 150)
big = 384
glyph = Image.new("L", (big, big), 0)
draw = ImageDraw.Draw(glyph)
ring = 30
draw.ellipse((ring // 2, ring // 2, big - ring // 2, big - ring // 2), outline=255, width=ring)
box = draw.textbbox((0, 0), "TG", font=font)
width, height = box[2] - box[0], box[3] - box[1]
draw.text(((big - width) / 2 - box[0], (big - height) / 2 - box[1]), "TG", font=font, fill=255)
for name, scale in DENSITIES.items():
    side = round(24 * scale)
    alpha = glyph.resize((side, side), Image.LANCZOS)
    white = Image.new("RGBA", (side, side), (255, 255, 255, 0))
    white.putalpha(alpha)
    save(white, res / f"drawable-{name}/ic_stat_tgcg.png")

# iPhone and iPad: opaque icons, the seal on white.
icons = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
contents = json.loads((icons / "Contents.json").read_text(encoding="utf-8"))
for entry in contents["images"]:
    points = float(entry["size"].split("x")[0])
    pixels = round(points * float(entry["scale"].rstrip("x")))
    icon = placed(pixels, 0.9, (255, 255, 255, 255)).convert("RGB")
    save(icon, icons / entry["filename"])

# iPhone launch screen: the seal, 168pt, on the storyboard's white.
launch = root / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
for suffix, scale in (("", 1), ("@2x", 2), ("@3x", 3)):
    save(placed(168 * scale, 1.0), launch / f"LaunchImage{suffix}.png")

print("done")
