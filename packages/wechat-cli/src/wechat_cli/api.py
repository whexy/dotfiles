"""HTTP client for the iLink bot backend that Tencent's OpenClaw Weixin plugin speaks."""

import base64
import json
import secrets
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

DEFAULT_BASE_URL = "https://ilinkai.weixin.qq.com"
CDN_BASE_URL = "https://novac2c.cdn.weixin.qq.com/c2c"

# The backend admits clients by app id and a packed client version. These are
# the values of @tencent-weixin/openclaw-weixin 2.4.9, the release this client
# was ported from; bump them together if the backend starts rejecting it.
APP_ID = "bot"
CHANNEL_VERSION = "2.4.9"
BOT_TYPE = "3"
BOT_AGENT = "wechat-cli/0.1.0"

LONG_POLL_TIMEOUT = 35.0
API_TIMEOUT = 15.0

STALE_TOKEN_ERRCODE = -14
# sendmessage without a usable context token; the bot cannot open a conversation.
NO_CONTEXT_RET = -2

type Json = dict[str, Any]


class WechatError(Exception):
    def __init__(self, message: str, ret: int | None = None) -> None:
        super().__init__(message)
        self.ret: int | None = ret


class SessionExpired(WechatError):
    def __init__(self) -> None:
        super().__init__("WeChat session expired; run `wechat login` again")


def _client_version(version: str) -> int:
    major, minor, patch = (int(p) for p in version.split("."))
    return (major & 0xFF) << 16 | (minor & 0xFF) << 8 | (patch & 0xFF)


def _common_headers() -> dict[str, str]:
    return {
        "iLink-App-Id": APP_ID,
        "iLink-App-ClientVersion": str(_client_version(CHANNEL_VERSION)),
    }


def _auth_headers(token: str | None) -> dict[str, str]:
    uin = str(secrets.randbits(32)).encode()
    headers = {
        "Content-Type": "application/json",
        "AuthorizationType": "ilink_bot_token",
        "X-WECHAT-UIN": base64.b64encode(uin).decode(),
        **_common_headers(),
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def base_info() -> Json:
    return {"channel_version": CHANNEL_VERSION, "bot_agent": BOT_AGENT}


def check(resp: Json, label: str) -> Json:
    code = resp.get("errcode") or resp.get("ret") or 0
    if code == STALE_TOKEN_ERRCODE:
        raise SessionExpired
    if code:
        errmsg = resp.get("errmsg") or "(none)"
        raise WechatError(f"{label}: ret={code} errmsg={errmsg}", code)
    return resp


def _open(request: urllib.request.Request, timeout: float, label: str) -> Json:
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise WechatError(f"{label}: HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        if isinstance(error.reason, TimeoutError):
            raise TimeoutError(label) from error
        raise WechatError(f"{label}: {error.reason}") from error
    return json.loads(body) if body.strip() else {}


class Client:
    def __init__(self, base_url: str = DEFAULT_BASE_URL, token: str | None = None) -> None:
        self.base_url: str = base_url.rstrip("/") + "/"
        self.token: str | None = token

    def post(self, endpoint: str, body: Json, *, timeout: float = API_TIMEOUT) -> Json:
        request = urllib.request.Request(
            urllib.parse.urljoin(self.base_url, endpoint),
            data=json.dumps({**body, "base_info": base_info()}).encode(),
            headers=_auth_headers(self.token),
            method="POST",
        )
        return _open(request, timeout, endpoint)

    def get(self, endpoint: str, *, timeout: float = API_TIMEOUT) -> Json:
        request = urllib.request.Request(
            urllib.parse.urljoin(self.base_url, endpoint), headers=_common_headers()
        )
        return _open(request, timeout, endpoint)

    # Login

    def fetch_qrcode(self, known_tokens: list[str]) -> Json:
        return self.post(
            f"ilink/bot/get_bot_qrcode?bot_type={BOT_TYPE}",
            {"local_token_list": known_tokens},
        )

    def qrcode_status(self, qrcode: str, verify_code: str | None = None) -> Json:
        query = {"qrcode": qrcode}
        if verify_code:
            query["verify_code"] = verify_code
        try:
            return self.get(
                f"ilink/bot/get_qrcode_status?{urllib.parse.urlencode(query)}",
                timeout=LONG_POLL_TIMEOUT,
            )
        except (TimeoutError, WechatError):
            # Long-poll expiry and gateway timeouts both mean "keep waiting".
            return {"status": "wait"}

    # Messaging

    def get_updates(self, cursor: str, timeout: float = LONG_POLL_TIMEOUT) -> Json:
        """One long poll. A client-side timeout leaves the cursor unchanged."""
        try:
            resp = self.post("ilink/bot/getupdates", {"get_updates_buf": cursor}, timeout=timeout)
        except TimeoutError:
            return {"msgs": [], "get_updates_buf": cursor}
        return check(resp, "getupdates")

    def send_message(self, msg: Json) -> Json:
        return check(self.post("ilink/bot/sendmessage", {"msg": msg}), "sendmessage")

    def get_upload_url(self, request: Json) -> Json:
        return check(self.post("ilink/bot/getuploadurl", request), "getuploadurl")
