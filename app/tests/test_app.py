import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import storage  # noqa: E402


@pytest.mark.parametrize("name, expected", [
    ("report.pdf", "report.pdf"),
    ("../../etc/passwd", "passwd"),
    ("C:\\temp\\x y.txt", "C__temp_x_y.txt"),
    (".hidden", "hidden"),
    ("", "file"),
])
def test_safe_filename(name, expected):
    assert storage.safe_filename(name) == expected


def test_local_store_round_trip(tmp_path):
    store = storage.LocalStore(str(tmp_path))
    store.put("ab12/sheet.txt", b"hello")
    assert store.get("ab12/sheet.txt") == b"hello"


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("UPLOAD_DIR", str(tmp_path))
    import app as app_module

    return app_module.app.test_client()


def test_create_job_requires_fields(client):
    assert client.post("/jobs", data={"customer": "A", "site": ""}).status_code == 400


def test_files_rejects_path_traversal(client):
    assert client.get("/files/../secret").status_code == 404
