"""Label fonts for contact sheets and filmstrips, from Nix store paths.

The wrapper sets VIDEO_EDIT_FONT to a Noto Sans CJK collection so labels
render Chinese transcript words; without it Pillow's built-in font is used.
"""

import os

from PIL import ImageFont

# Index of the Simplified Chinese face in NotoSansCJK-VF.otf.ttc.
CJK_SC_INDEX = 2


def load(size):
    path = os.environ.get("VIDEO_EDIT_FONT")
    if path and os.path.exists(path):
        try:
            font = ImageFont.truetype(path, size, index=CJK_SC_INDEX)
        except OSError:
            font = ImageFont.truetype(path, size)
        try:
            font.set_variation_by_name("Regular")
        except (OSError, ValueError):
            pass
        return font
    return ImageFont.load_default(size)
