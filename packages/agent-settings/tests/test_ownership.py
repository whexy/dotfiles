import pytest

from agent_settings.documents import Table
from agent_settings.errors import SettingsError
from agent_settings.ownership import merge_owned


def test_writes_desired_values_beside_user_values() -> None:
    doc: Table = {"user": 1, "nested": {"user": True}}
    merge_owned(doc, {}, {"owned": 2, "nested": {"owned": False}})
    assert doc == {"user": 1, "owned": 2, "nested": {"user": True, "owned": False}}


def test_retires_only_unchanged_values() -> None:
    doc: Table = {"kept": "user edit", "dropped": "nix"}
    merge_owned(doc, {"kept": "nix", "dropped": "nix"}, {})
    assert doc == {"kept": "user edit"}


def test_retired_table_is_removed_once_empty() -> None:
    doc: Table = {"servers": {"old": {"command": "a"}}, "mine": {"old": 1, "user": 2}}
    merge_owned(doc, {"servers": {"old": {"command": "a"}}, "mine": {"old": 1}}, {})
    assert doc == {"mine": {"user": 2}}


def test_lists_keep_user_items_and_replace_owned_ones() -> None:
    doc: Table = {"allow": ["user", "old", "new"]}
    merge_owned(doc, {"allow": ["old"]}, {"allow": ["new"]})
    assert doc == {"allow": ["user", "new"]}


def test_uninterpretable_ownership_claims_nothing() -> None:
    doc: Table = {"servers": {"user": 1}, "allow": ["user"]}
    merge_owned(doc, {"servers": "scalar", "allow": "scalar"}, {"servers": {}, "allow": ["new"]})
    assert doc == {"servers": {"user": 1}, "allow": ["user", "new"]}


@pytest.mark.parametrize(("doc", "desired"), [({"k": 1}, {"k": {}}), ({"k": 1}, {"k": []})])
def test_refuses_to_replace_mismatched_user_values(doc: Table, desired: Table) -> None:
    with pytest.raises(SettingsError):
        merge_owned(doc, {}, desired)
