"""Media travels through the WeChat CDN encrypted with AES-128-ECB."""

import base64
import hashlib
import mimetypes
import re
import secrets
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Literal

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

from wechat_cli.api import API_TIMEOUT, CDN_BASE_URL, Client, Json, WechatError

type Kind = Literal["image", "video", "file"]

ITEM_TEXT = 1
ITEM_IMAGE = 2
ITEM_VOICE = 3
ITEM_FILE = 4
ITEM_VIDEO = 5

UPLOAD_MEDIA_TYPE: dict[Kind, int] = {"image": 1, "video": 2, "file": 3}


def encrypt(plaintext: bytes, key: bytes) -> bytes:
    padder = padding.PKCS7(128).padder()
    encryptor = Cipher(algorithms.AES(key), modes.ECB()).encryptor()
    padded = padder.update(plaintext) + padder.finalize()
    return encryptor.update(padded) + encryptor.finalize()


def decrypt(ciphertext: bytes, key: bytes) -> bytes:
    decryptor = Cipher(algorithms.AES(key), modes.ECB()).decryptor()
    unpadder = padding.PKCS7(128).unpadder()
    padded = decryptor.update(ciphertext) + decryptor.finalize()
    return unpadder.update(padded) + unpadder.finalize()


def padded_size(size: int) -> int:
    return (size // 16 + 1) * 16


def parse_aes_key(aes_key: str) -> bytes:
    """Images carry base64 of the raw key; files, voice and video base64 of its hex."""
    decoded = base64.b64decode(aes_key)
    if len(decoded) == 16:
        return decoded
    if len(decoded) == 32 and re.fullmatch(rb"[0-9a-fA-F]{32}", decoded):
        return bytes.fromhex(decoded.decode())
    raise WechatError(f"unrecognised aes_key encoding ({len(decoded)} bytes)")


def kind_of(path: Path, forced: str | None = None) -> Kind:
    match forced:
        case "image" | "video" | "file":
            return forced
        case _:
            pass
    mime = mimetypes.guess_type(path.name)[0] or ""
    if mime.startswith("image/"):
        return "image"
    if mime.startswith("video/"):
        return "video"
    return "file"


def _cdn_post(url: str, body: bytes) -> str:
    request = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/octet-stream"}, method="POST"
    )
    last: Exception | None = None
    for _ in range(3):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                param = response.headers.get("x-encrypted-param")
            if not param:
                raise WechatError("CDN upload response missing x-encrypted-param")
            return param
        except urllib.error.HTTPError as error:
            message = error.headers.get("x-error-message") or f"HTTP {error.code}"
            if 400 <= error.code < 500:
                raise WechatError(f"CDN upload rejected: {message}") from error
            last = WechatError(f"CDN upload failed: {message}")
        except (urllib.error.URLError, TimeoutError, WechatError) as error:
            last = error
    raise WechatError(f"CDN upload failed after 3 attempts: {last}")


def upload(client: Client, path: Path, to: str, kind: Kind) -> Json:
    """Upload a local file and return the message item that references it."""
    plaintext = path.read_bytes()
    key = secrets.token_bytes(16)
    filekey = secrets.token_hex(16)
    ciphertext_size = padded_size(len(plaintext))
    resp = client.get_upload_url(
        {
            "filekey": filekey,
            "media_type": UPLOAD_MEDIA_TYPE[kind],
            "to_user_id": to,
            "rawsize": len(plaintext),
            "rawfilemd5": hashlib.md5(plaintext).hexdigest(),
            "filesize": ciphertext_size,
            "no_need_thumb": True,
            "aeskey": key.hex(),
        }
    )
    url = (resp.get("upload_full_url") or "").strip()
    if not url:
        param = resp.get("upload_param")
        if not param:
            raise WechatError("getuploadurl returned no upload URL")
        query = urllib.parse.urlencode({"encrypted_query_param": param, "filekey": filekey})
        url = f"{CDN_BASE_URL}/upload?{query}"
    download_param = _cdn_post(url, encrypt(plaintext, key))

    media = {
        "encrypt_query_param": download_param,
        "aes_key": base64.b64encode(key.hex().encode()).decode(),
        "encrypt_type": 1,
    }
    match kind:
        case "image":
            return {"type": ITEM_IMAGE, "image_item": {"media": media, "mid_size": ciphertext_size}}
        case "video":
            return {
                "type": ITEM_VIDEO,
                "video_item": {"media": media, "video_size": ciphertext_size},
            }
        case "file":
            return {
                "type": ITEM_FILE,
                "file_item": {"media": media, "file_name": path.name, "len": str(len(plaintext))},
            }


MEDIA_FIELDS: dict[int, tuple[str, str]] = {
    ITEM_IMAGE: ("image_item", "image.jpg"),
    ITEM_VOICE: ("voice_item", "voice.silk"),
    ITEM_FILE: ("file_item", "file.bin"),
    ITEM_VIDEO: ("video_item", "video.mp4"),
}


def _media_of(item: Json) -> tuple[Json, str | None, str]:
    """Return the CDN reference, its AES key, and a file name for an item."""
    if item.get("type") not in MEDIA_FIELDS:
        raise WechatError("item carries no media")
    field, name = MEDIA_FIELDS[item["type"]]
    body: Json = item.get(field) or {}
    media: Json = body.get("media") or {}
    key: str | None = media.get("aes_key")
    # An image's hex key is authoritative over media.aes_key.
    if hex_key := body.get("aeskey"):
        key = base64.b64encode(bytes.fromhex(hex_key)).decode()
    return media, key, body.get("file_name") or name


def download(item: Json, dest: Path, stem: str) -> Path:
    media, key, name = _media_of(item)
    url = media.get("full_url")
    if not url:
        param = media.get("encrypt_query_param")
        if not param:
            raise WechatError("media has no download reference")
        url = f"{CDN_BASE_URL}/download?{urllib.parse.urlencode({'encrypted_query_param': param})}"
    try:
        with urllib.request.urlopen(url, timeout=API_TIMEOUT * 4) as response:
            data: bytes = response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        raise WechatError(f"media download failed: {error}") from error
    if key:
        data = decrypt(data, parse_aes_key(key))
    dest.mkdir(parents=True, exist_ok=True)
    # Prefix the message id so two attachments with the same name never collide.
    path = dest / f"{stem}-{Path(name).name}"
    path.write_bytes(data)
    return path
