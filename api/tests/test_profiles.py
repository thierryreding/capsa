from __future__ import annotations

import json
import logging
import os

import pytest
from conftest import DEMO_PROFILE

from capsa.profile_io import dump_profile, load_profile
from capsa.profiles import ProfileStore


@pytest.fixture
def profile_dir(tmp_path):
    d = tmp_path / "profiles"
    (d / "sub").mkdir(parents=True)
    (d / "demo.yaml").write_text(DEMO_PROFILE.read_text(encoding="utf-8"), encoding="utf-8")
    other = load_profile(DEMO_PROFILE)
    other["profile"]["id"] = "other-demo"
    other["profile"]["title"] = "Other"
    (d / "sub" / "other.yaml").write_text(dump_profile(other), encoding="utf-8")
    return d


# --- store ----------------------------------------------------------------


def test_store_loads_recursively(profile_dir):
    store = ProfileStore(profile_dir)
    assert [p.id for p in store.all()] == ["demo-latin", "other-demo"]
    demo = store.get("demo-latin")
    assert json.loads(demo.body) == load_profile(DEMO_PROFILE)
    assert demo.etag.startswith('"') and len(demo.etag) == 34
    assert "u1-nauta" in demo.entry_ids


def test_store_skips_invalid_and_duplicate_profiles(profile_dir, caplog):
    (profile_dir / "broken.yaml").write_text("profile: [", encoding="utf-8")
    bad = load_profile(DEMO_PROFILE)
    bad["profile"]["id"] = "bad-one"
    del bad["units"][0]["entries"][0]["lemma"]
    (profile_dir / "bad.yaml").write_text(dump_profile(bad), encoding="utf-8")
    (profile_dir / "dup.yaml").write_text(DEMO_PROFILE.read_text("utf-8"), encoding="utf-8")
    with caplog.at_level(logging.ERROR):
        ids = [p.id for p in ProfileStore(profile_dir).all()]
    assert ids == ["demo-latin", "other-demo"]
    text = caplog.text
    assert "broken.yaml: cannot be loaded" in text
    assert "bad.yaml: 1 validation errors" in text
    assert "already loaded" in text
    assert "nauta" not in text  # never log profile content


def test_store_reloads_changed_files(profile_dir):
    store = ProfileStore(profile_dir)
    old = store.get("demo-latin").etag
    data = load_profile(profile_dir / "demo.yaml")
    data["profile"]["revision"] = 2
    path = profile_dir / "demo.yaml"
    path.write_text(dump_profile(data), encoding="utf-8")
    os.utime(path, ns=(1, 1))  # make sure the signature changes even within one tick
    new = store.get("demo-latin")
    assert new.revision == 2 and new.etag != old
    (profile_dir / "sub" / "other.yaml").unlink()
    assert store.get("other-demo") is None


def test_store_missing_directory(tmp_path):
    assert ProfileStore(tmp_path / "nope").all() == []


# --- API ------------------------------------------------------------------


def test_profiles_need_login(api):
    c = api.client()
    assert c.get("/api/v1/profiles").status_code == 401
    assert c.get("/api/v1/profiles/demo-latin").status_code == 401


def test_learner_sees_only_released_profiles(api):
    api.add_user("lena")
    api.add_user("max", profiles=["demo-latin"])
    assert api.login("lena").get("/api/v1/profiles").json() == []
    listed = api.login("max").get("/api/v1/profiles").json()
    assert [p["id"] for p in listed] == ["demo-latin"]
    assert listed[0]["revision"] == 1 and listed[0]["translation_langs"] == ["de", "fr"]


def test_unreleased_profile_looks_like_missing(api):
    api.add_user("lena")
    c = api.login("lena")
    a = c.get("/api/v1/profiles/demo-latin")
    b = c.get("/api/v1/profiles/does-not-exist")
    assert a.status_code == b.status_code == 404
    assert a.json() == b.json()


def test_admin_sees_all_profiles(api):
    api.add_user("papa", role="admin")
    c = api.login("papa")
    assert [p["id"] for p in c.get("/api/v1/profiles").json()] == ["demo-latin"]
    assert c.get("/api/v1/profiles/demo-latin").status_code == 200


def test_profile_document_and_etag(api):
    api.add_user("max", profiles=["demo-latin"])
    c = api.login("max")
    r = c.get("/api/v1/profiles/demo-latin")
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/json"
    assert r.headers["cache-control"] == "private, no-cache"
    assert r.json() == load_profile(DEMO_PROFILE)
    etag = r.headers["etag"]
    assert c.get("/api/v1/profiles").json()[0]["etag"] == etag

    not_modified = c.get("/api/v1/profiles/demo-latin", headers={"If-None-Match": etag})
    assert not_modified.status_code == 304 and not_modified.content == b""
    weak = c.get("/api/v1/profiles/demo-latin", headers={"If-None-Match": f'"x", W/{etag}'})
    assert weak.status_code == 304
    stale = c.get("/api/v1/profiles/demo-latin", headers={"If-None-Match": '"stale"'})
    assert stale.status_code == 200
