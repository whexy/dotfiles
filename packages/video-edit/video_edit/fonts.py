"""Label fonts for contact sheets and filmstrips, from Nix store paths.

The wrapper sets VIDEO_EDIT_FONT to a Noto Sans CJK collection so labels
render Chinese transcript words; without it Pillow's built-in font is used.
"""

import contextlib
import os
from pathlib import Path

from PIL import ImageFont

# Index of the Simplified Chinese face in NotoSansCJK-VF.otf.ttc.
CJK_SC_INDEX = 2


def load(size):
    path = os.environ.get("VIDEO_EDIT_FONT")
    if path and Path(path).exists():
        try:
            font = ImageFont.truetype(path, size, index=CJK_SC_INDEX)
        except OSError:
            font = ImageFont.truetype(path, size)
        with contextlib.suppress(OSError, ValueError):
            font.set_variation_by_name("Regular")
        return font
    return ImageFont.load_default(size)
