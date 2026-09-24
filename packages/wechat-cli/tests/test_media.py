import base64
from pathlib import Path

import pytest

from wechat_cli import media
from wechat_cli.api import WechatError

KEY = bytes(range(16))


def test_round_trip_pads_to_block() -> None:
    for size in (0, 15, 16, 17):
        ciphertext = media.encrypt(b"x" * size, KEY)
        assert len(ciphertext) == media.padded_size(size)
        assert media.decrypt(ciphertext, KEY) == b"x" * size


def test_parse_aes_key_accepts_raw_and_hex_encodings() -> None:
    assert media.parse_aes_key(base64.b64encode(KEY).decode()) == KEY
    assert media.parse_aes_key(base64.b64encode(KEY.hex().encode()).decode()) == KEY
    with pytest.raises(WechatError):
        media.parse_aes_key(base64.b64encode(b"short").decode())


def test_kind_of() -> None:
    assert media.kind_of(Path("a.png")) == "image"
    assert media.kind_of(Path("a.mp4")) == "video"
    assert media.kind_of(Path("a.pdf")) == "file"
    assert media.kind_of(Path("a.png"), "file") == "file"


def test_image_hex_key_wins_over_media_key() -> None:
    item = {
        "type": media.ITEM_IMAGE,
        "image_item": {"aeskey": KEY.hex(), "media": {"aes_key": "ignored"}},
    }
    _, key, name = media._media_of(item)
    assert key is not None
    assert media.parse_aes_key(key) == KEY
    assert name == "image.jpg"
