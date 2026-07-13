#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parent
APP_ICON_SOURCE = ROOT / "7D94C64E-CA67-48F2-AC06-9AD0E193B8FF.png"
STATUS_ICON_SOURCE = ROOT / "0A68F333-38D5-43E2-9BB9-1441B2A92A31.png"
ICONSET = ROOT / "AppIcon.iconset"
STATUS_ICON = ROOT / "PythiaStatusTemplate.png"

ICONSET.mkdir(exist_ok=True)


def rounded_mask(size: int, radius: int) -> Image.Image:
    scale = 4
    mask = Image.new("L", (size * scale, size * scale), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * scale - 1, size * scale - 1),
        radius=radius * scale,
        fill=255,
    )
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def square_cover(image: Image.Image, size: int) -> Image.Image:
    image = image.convert("RGBA")
    scale = max(size / image.width, size / image.height)
    resized = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - size) // 2
    top = (resized.height - size) // 2
    return resized.crop((left, top, left + size, top + size))


def make_app_icon(size: int) -> Image.Image:
    icon = square_cover(Image.open(APP_ICON_SOURCE), size)
    icon.putalpha(rounded_mask(size, int(size * 0.2207)))
    return icon


def make_status_template() -> Image.Image:
    source = Image.open(STATUS_ICON_SOURCE).convert("RGBA")
    alpha = source.getchannel("A")
    # Use the existing alpha, but suppress low-opacity background haze and
    # normalize the remaining artwork into a crisp macOS template image.
    alpha = alpha.point(lambda value: 0 if value < 38 else min(255, int((value - 38) * 1.45)))
    bbox = alpha.getbbox()
    if bbox:
        pad = 18
        bbox = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(source.width, bbox[2] + pad),
            min(source.height, bbox[3] + pad),
        )
        alpha = alpha.crop(bbox)
    alpha = ImageOps.autocontrast(alpha)
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.35))

    canvas_size = 36
    target = 34
    scale = min(target / alpha.width, target / alpha.height)
    resized = alpha.resize((round(alpha.width * scale), round(alpha.height * scale)), Image.Resampling.LANCZOS)
    canvas_alpha = Image.new("L", (canvas_size, canvas_size), 0)
    canvas_alpha.paste(resized, ((canvas_size - resized.width) // 2, (canvas_size - resized.height) // 2))

    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 255))
    image.putalpha(canvas_alpha)
    return image


SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

for filename, size in SIZES.items():
    make_app_icon(size).save(ICONSET / filename)

make_status_template().save(STATUS_ICON)
print(ICONSET)
print(STATUS_ICON)
