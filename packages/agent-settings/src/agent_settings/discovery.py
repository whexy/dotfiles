"""Live model lists named by discovery templates, fetched only while picking."""

import json
from http.client import HTTPResponse
from typing import cast, override
from urllib.request import HTTPRedirectHandler, Request, build_opener

from agent_settings.catalog import Discover, Entry
from agent_settings.credentials import read_secrets
from agent_settings.documents import is_list, is_table
from agent_settings.errors import SettingsError


class _RefuseRedirect(HTTPRedirectHandler):
    # urllib forwards custom headers across origins, so a redirect would hand
    # the Cloudflare Access token to whatever origin it names.
    @override
    def redirect_request(self, *_args: object, **_kwargs: object) -> None:
        return None


def served_models(template: Entry, discover: Discover) -> list[str]:
    """IDs of the models the template's endpoint serves, sorted."""
    secrets = read_secrets(template.get("secrets", {}))
    headers = {
        "Authorization": f"Bearer {secrets[discover['keyEnv']]}",
        # Cloudflare's bot protection rejects urllib's default User-Agent.
        "User-Agent": "agent-settings",
    }
    headers |= {header: secrets[env] for header, env in template.get("secretHeaders", {}).items()}
    opener = build_opener(_RefuseRedirect)
    try:
        request = Request(discover["url"], headers=headers)
        with cast(HTTPResponse, opener.open(request, timeout=10)) as response:
            payload = cast(object, json.load(response))
    except (OSError, ValueError) as error:
        raise SettingsError(f"{template['label']}: model discovery failed: {error}") from error
    data = payload.get("data") if is_table(payload) else None
    if not is_list(data):
        raise SettingsError(f"{template['label']}: model discovery returned no model list")
    models = {model.get("id") for model in data if is_table(model)}
    return sorted(model for model in models if isinstance(model, str) and model)
