"""HTTP reads with retries."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from typing import Any

from . import UpdateError

_ATTEMPTS = 3


def fetch_bytes(url: str) -> bytes:
    headers = {"User-Agent": "dotfiles-update"}
    # Unauthenticated GitHub API calls share a small per-IP limit.
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    for attempt in range(1, _ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code < 500 or attempt == _ATTEMPTS:
                raise UpdateError(f"GET {url}: HTTP {error.code}") from error
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt == _ATTEMPTS:
                raise UpdateError(f"GET {url}: {error}") from error
        time.sleep(attempt * 2)
    raise AssertionError("unreachable")


def fetch_text(url: str) -> str:
    return fetch_bytes(url).decode()


def fetch_json(url: str) -> Any:
    return json.loads(fetch_bytes(url))
