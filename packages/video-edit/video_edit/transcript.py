"""Reading `transcribe --format json` output and comparing spoken text."""

from pathlib import Path
import unicodedata

from .common import UsageError, read_json


def load(path):
    """(transcript dict, flat word list) from a cached transcribe JSON.

    Each word gets `index`, its position in source order, which every
    other command uses to name it.
    """
    path = Path(path)
    if not path.exists():
        raise UsageError(
            f"no transcript at {path}: run `transcribe <main> --format json "
            f"-o {path}` once"
        )
    data = read_json(path)
    try:
        raw = [w for seg in data["segments"] for w in seg["words"]]
        words = [
            {
                "word": str(w["word"]).strip(),
                "start": float(w["start"]),
                "end": float(w["end"]),
                "filler": bool(w.get("filler")),
                "stumble": bool(w.get("stumble")),
            }
            for w in raw
        ]
    except (KeyError, TypeError, ValueError) as err:
        raise UsageError(f"{path} is not `transcribe --format json` output") from err
    words = [w for w in words if w["word"]]
    words.sort(key=lambda w: (w["start"], w["end"]))
    for i, w in enumerate(words):
        w["index"] = i
        w["end"] = max(w["end"], w["start"])
    return data, words


def is_cjk(ch):
    code = ord(ch)
    return (
        0x3400 <= code <= 0x4DBF
        or 0x4E00 <= code <= 0x9FFF
        or 0xF900 <= code <= 0xFAFF
        or 0x3040 <= code <= 0x30FF
        or 0xAC00 <= code <= 0xD7AF
        or 0x20000 <= code <= 0x2FA1F
    )


def join(tokens):
    """Join whisper word pieces without spaces.

    whisper-1 splits English into sub-word pieces on this material
    ("ag ent", "sk ills", "n ix OS"), so spaces between pieces are wrong
    far more often than missing ones.
    """
    return "".join(token.strip() for token in tokens)


def units(text):
    """Comparison units: every letter, digit or CJK character, lowercased.

    Punctuation and whitespace are dropped, so whisper's word pieces
    ("k ubernetes") compare equal to the joined word and a diff of Chinese
    ignores how either side punctuated it.
    """
    return [ch.lower() for ch in unicodedata.normalize("NFKC", text) if ch.isalnum()]


def display_width(text):
    """Subtitle width: full-width characters count 1, half-width 0.5."""
    return sum(
        1.0 if unicodedata.east_asian_width(ch) in ("W", "F") else 0.5
        for ch in text
        if ch != "\n"
    )
