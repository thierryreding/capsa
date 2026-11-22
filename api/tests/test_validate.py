from __future__ import annotations

import pytest
from conftest import DEMO_PROFILE, private_profiles

from capsa.cli import main
from capsa.profile_io import DuplicateKeyError, parse_profile
from capsa.validate import validate_profile


def errors(data) -> list[str]:
    return [str(i) for i in validate_profile(data) if i.level == "error"]


def warnings(data) -> list[str]:
    return [str(i) for i in validate_profile(data) if i.level == "warning"]


def entry(data, unit_index, entry_id):
    return next(e for e in data["units"][unit_index]["entries"] if e["id"] == entry_id)


def test_demo_profile_is_clean(demo):
    assert validate_profile(demo) == []


@pytest.mark.parametrize("path", private_profiles(), ids=lambda p: p.name)
def test_private_profiles_are_valid(path):
    # Runs only on machines that have the private profiles; asserts nothing about content.
    from capsa.profile_io import load_profile

    assert errors(load_profile(path)) == []


# --- schema ---------------------------------------------------------------


def test_unknown_field_is_rejected(demo):
    entry(demo, 0, "u1-nauta")["lemmma"] = "typo"
    assert any("lemmma" in e for e in errors(demo))


def test_missing_lemma_is_rejected(demo):
    del entry(demo, 0, "u1-nauta")["lemma"]
    assert any("'lemma' is a required property" in e for e in errors(demo))


def test_bad_id_pattern_is_rejected(demo):
    entry(demo, 0, "u1-nauta")["id"] = "U1 Nauta"
    assert any("units[0].entries[0].id" in e for e in errors(demo))


def test_bad_note_kind_is_rejected(demo):
    demo["units"][0]["notes"][0]["kind"] = "trivia"
    assert any("units[0].notes[0].kind" in e for e in errors(demo))


def test_wrong_schema_version(demo):
    demo["schema_version"] = 2
    assert any(e.startswith("error: schema_version") for e in errors(demo))


def test_duplicate_yaml_keys_are_rejected():
    with pytest.raises(DuplicateKeyError, match="duplicate key 'lemma'"):
        parse_profile("a:\n  lemma: x\n  lemma: y\n")


# --- cross references -----------------------------------------------------


def test_duplicate_entry_id(demo):
    entry(demo, 1, "u2-numquam")["id"] = "u1-nauta"
    assert any("duplicate entry id 'u1-nauta'" in e for e in errors(demo))


def test_duplicate_unit_id_and_number(demo):
    demo["units"][1]["id"] = "u1"
    demo["units"][1]["number"] = 1
    errs = errors(demo)
    assert any("duplicate unit id 'u1'" in e for e in errs)
    assert any("duplicate unit number 1" in e for e in errs)


def test_missing_required_translation(demo):
    entry(demo, 0, "u1-ventus")["tr"] = {"fr": ["le vent"]}
    assert any("'u1-ventus' lacks required translation 'de'" in e for e in errors(demo))


def test_deprecated_entry_may_lack_required_translation(demo):
    e = entry(demo, 0, "u1-ventus")
    e["tr"] = {"fr": ["le vent"]}
    e["deprecated"] = True
    assert errors(demo) == []


def test_translation_language_not_declared(demo):
    entry(demo, 0, "u1-ventus")["tr"]["es"] = ["el viento"]
    assert any("tr.es: language not in translation_langs" in e for e in errors(demo))


def test_required_lang_must_be_a_translation_lang(demo):
    demo["profile"]["required_translation_lang"] = "en"
    assert any("must be listed in translation_langs" in e for e in errors(demo))


def test_example_needs_source_text(demo):
    ex = entry(demo, 0, "u1-navigat")["examples"][0]
    del ex["la"]
    assert any("missing source text 'la'" in e for e in errors(demo))


def test_matching_language_must_be_known(demo):
    demo["profile"]["matching"]["optional_articles"]["es"] = ["el "]
    assert any("matching.optional_articles.es: unknown language" in e for e in errors(demo))


def test_review_reference_unknown(demo):
    demo["units"][1]["review"].append("u1-nope")
    assert any("unknown entry 'u1-nope'" in e for e in errors(demo))


def test_review_reference_must_be_earlier(demo):
    demo["units"][1]["review"].append("u2-numquam")
    assert any("'u2-numquam' is not from an earlier unit" in e for e in errors(demo))


def test_review_of_deprecated_entry_warns(demo):
    entry(demo, 0, "u1-nauta")["deprecated"] = True
    assert errors(demo) == []
    assert any("'u1-nauta' is deprecated" in w for w in warnings(demo))


def test_entry_id_prefix_warns(demo):
    entry(demo, 1, "u2-numquam")["id"] = "u1-numquam"
    assert errors(demo) == []
    assert any("does not start with unit id 'u2-'" in w for w in warnings(demo))


def test_table_row_width(demo):
    demo["units"][1]["tables"][0]["rows"][0].append("extra")
    assert any("has 4 cells, expected 3" in e for e in errors(demo))


# --- CLI ------------------------------------------------------------------


def test_cli_ok(capsys):
    assert main(["validate", str(DEMO_PROFILE)]) == 0
    out = capsys.readouterr().out
    assert "ok (2 units, 19 entries, 0 errors, 0 warnings)" in out


def test_cli_reports_errors(tmp_path, capsys):
    bad = tmp_path / "bad.yaml"
    bad.write_text(
        DEMO_PROFILE.read_text(encoding="utf-8").replace("review: [u1-nauta", "review: [u9-x"),
        encoding="utf-8",
    )
    assert main(["validate", str(bad)]) == 1
    assert "unknown entry 'u9-x'" in capsys.readouterr().out


def test_cli_unloadable_file(tmp_path, capsys):
    assert main(["validate", str(tmp_path / "missing.yaml")]) == 1
    assert "cannot load" in capsys.readouterr().err
