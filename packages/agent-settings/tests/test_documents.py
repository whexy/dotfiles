import json
from pathlib import Path

import pytest

from agent_settings.documents import edit_document, read_document
from agent_settings.errors import SettingsError


def test_toml_comments_survive_edits(home: Path) -> None:
    path = home / "config.toml"
    path.write_text('# keep this\nmodel = "user"\n')
    with edit_document(path) as doc:
        doc["added"] = True
    assert path.read_text() == '# keep this\nmodel = "user"\nadded = true\n'


def test_conflicting_writer_wins(home: Path) -> None:
    path = home / "config.json"
    path.write_text("{}")
    with pytest.raises(SettingsError), edit_document(path) as doc:
        doc["mine"] = True
        path.write_text('{"other":true}')
    assert json.loads(path.read_text()) == {"other": True}


def test_non_nix_symlink_is_not_replaced(home: Path) -> None:
    target = home / "config.json"
    target.write_text("{}")
    link = home / "link.json"
    link.symlink_to(target)
    with pytest.raises(SettingsError), edit_document(link) as doc:
        doc["mine"] = True
    assert link.is_symlink()


def test_non_object_documents_are_refused(home: Path) -> None:
    path = home / "config.json"
    path.write_text("[]")
    with pytest.raises(SettingsError):
        read_document(path)
