"""Reconcile Nix-maintained values into documents the user also edits.

A value is owned when the previous reconciliation wrote it. Desired values are
always written. Owned values Nix no longer wants are removed only while the user
has left them unchanged. Everything else in the document belongs to the user.
"""

from agent_settings.documents import Table, child_table, is_list, is_table, table_or_empty
from agent_settings.errors import SettingsError


def merge_owned(doc: Table, previous: Table, desired: Table) -> None:
    """Write `desired` into `doc`, retiring what `previous` owned and `desired` dropped."""
    for key, old in previous.items():
        if key not in desired and key in doc:
            _retire(doc, key, old)
    for key, value in desired.items():
        _apply(doc, key, value, previous.get(key))


def _retire(doc: Table, key: str, old: object) -> None:
    current = doc[key]
    if is_table(old) and is_table(current):
        merge_owned(current, old, {})
        if not current:
            del doc[key]
    elif is_list(old) and is_list(current):
        doc[key] = [item for item in current if item not in old]
    elif current == old:
        del doc[key]


def _apply(doc: Table, key: str, value: object, old: object) -> None:
    if is_table(value):
        # An ownership record we cannot interpret claims nothing.
        merge_owned(child_table(doc, key), table_or_empty(old), value)
    elif is_list(value):
        existing = doc.get(key, [])
        if not is_list(existing):
            raise SettingsError(f"expected a list at {key}")
        retired = old if is_list(old) else []
        user_items = [item for item in existing if item not in retired and item not in value]
        doc[key] = user_items + value
    else:
        doc[key] = value
