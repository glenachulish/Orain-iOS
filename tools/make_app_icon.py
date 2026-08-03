#!/usr/bin/env python3
"""Generate Òrain's app icon set.

The icon is the wordmark: "Òrain" in a bold serif, cream on rust — the same
rust the app uses for chord names, so the icon and the thing it opens are
visibly the same object.

Xcode 26 asks for three 1024×1024 variants:

  light   what you see normally
  dark    for a dark home screen; same mark, deeper ground
  tinted  greyscale, which iOS recolours to match the user's home screen

WHY THIS IS A SCRIPT AND NOT A PNG IN A FOLDER
    So the icon can be regenerated when something changes — a different rust,
    a tweak to the spacing — without anyone having to remember what was done
    last time or open an image editor. The PNGs it writes are committed too;
    this is the record of how they were made.

Run:  python3 tools/make_app_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
WORD = "Òrain"

# The app's chord colour, and a parchment that isn't quite white.
RUST = (158, 71, 36)
CREAM = (247, 240, 228)
# Dark-mode ground: the same hue taken down, rather than a neutral black, so
# the two variants read as the same icon in different light.
DEEP_RUST = (74, 32, 16)

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"

# The word occupies this much of the icon's width. Deliberately short of the
# edges: iOS rounds the corners hard, and a wordmark that fills the square
# looks cramped once the mask is applied.
WIDTH_FRACTION = 0.66

OUT = Path(__file__).resolve().parent.parent / "Orain/Orain/Assets.xcassets/AppIcon.appiconset"


def fitted_font(draw: ImageDraw.ImageDraw, text: str, target_width: int) -> ImageFont.FreeTypeFont:
    """The largest size at which the word still fits the target width."""
    size = 700
    while size > 20:
        font = ImageFont.truetype(FONT, size)
        box = draw.textbbox((0, 0), text, font=font)
        if box[2] - box[0] <= target_width:
            return font
        size -= 2
    return ImageFont.truetype(FONT, 20)


def render(background: tuple[int, int, int], ink: tuple[int, int, int], path: Path) -> None:
    image = Image.new("RGB", (SIZE, SIZE), background)
    draw = ImageDraw.Draw(image)

    font = fitted_font(draw, WORD, int(SIZE * WIDTH_FRACTION))
    box = draw.textbbox((0, 0), WORD, font=font)
    width, height = box[2] - box[0], box[3] - box[1]

    # Optically centred rather than mathematically: the grave accent adds
    # height at the top that the eye doesn't read as part of the word, so
    # centring on the full bounding box sits the word slightly low.
    x = (SIZE - width) / 2 - box[0]
    y = (SIZE - height) / 2 - box[1] + SIZE * 0.02

    draw.text((x, y), WORD, font=font, fill=ink)
    image.save(path)
    print(f"wrote {path.name}")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    render(RUST, CREAM, OUT / "icon-1024.png")
    render(DEEP_RUST, CREAM, OUT / "icon-1024-dark.png")
    # Tinted: iOS wants greyscale artwork and applies the colour itself.
    render((0, 0, 0), (255, 255, 255), OUT / "icon-1024-tinted.png")

    contents = """{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-1024-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
    (OUT / "Contents.json").write_text(contents, encoding="utf-8")
    print("wrote Contents.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
