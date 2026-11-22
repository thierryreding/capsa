from __future__ import annotations

import csv

import pytest

from capsa.cli import main
from capsa.csv_import import CsvImportError, ProfileMeta, rows_to_profile, slug, split_meanings
from capsa.lint import lint_profile
from capsa.profile_io import load_profile
from capsa.validate import validate_profile

META = ProfileMeta(id="test-words", title="Test", source_lang="la", translation_lang="de")

CSV = """unit;lemma;info;translation
1;nauta;m.;der Seemann, der Matrose
1;nāvigāre;nāvigō;"segeln; (mit dem Schiff) fahren"
2;  ventus ;m.;der Wind
1;nauta;m.;der Schiffer
"""


def rows(text: str) -> list[list[str]]:
    return list(csv.reader(text.splitlines(), delimiter=";"))


def test_slug():
    assert slug("nāvigāre") == "navigare"
    assert slug("ego/mē") == "ego-me"
    assert slug("Cavē!") == "cave"
    assert slug("!!") == "entry"


@pytest.mark.parametrize(
    ("text", "meanings"),
    [
        ("der Seemann, der Matrose", ["der Seemann", "der Matrose"]),
        ("segeln; (mit dem Schiff) fahren", ["segeln", "(mit dem Schiff) fahren"]),
        ("über (… hinüber, … hin), jenseits", ["über (… hinüber, … hin)", "jenseits"]),
        ("  fern  ", ["fern"]),
        (" , ", []),
    ],
)
def test_split_meanings(text, meanings):
    assert split_meanings(text) == meanings


def test_rows_to_profile():
    data = rows_to_profile(rows(CSV), META)
    assert validate_profile(data) == []
    assert [i.code for i in lint_profile(data)] == ["duplicate-lemma"]  # nauta twice
    u1, u2 = data["units"]
    assert (u1["id"], u1["number"], u2["id"]) == ("u1", 1, "u2")
    assert [e["id"] for e in u1["entries"]] == ["u1-nauta", "u1-navigare", "u1-nauta-2"]
    assert u1["entries"][1] == {
        "id": "u1-navigare",
        "lemma": "nāvigāre",
        "info": "nāvigō",
        "tr": {"de": ["segeln", "(mit dem Schiff) fahren"]},
    }
    assert u2["entries"][0]["lemma"] == "ventus"


def test_header_is_optional_and_blank_lines_skipped():
    data = rows_to_profile(rows("3;procul;;fern\n\n"), META)
    assert data["units"][0]["entries"] == [
        {"id": "u3-procul", "lemma": "procul", "tr": {"de": ["fern"]}}
    ]


def test_problems_are_collected_with_line_numbers():
    bad = "unit;lemma;info;translation\nx;nauta;m.;Seemann\n1;;m.;Seemann\n1;nauta;m.;\n1;nauta\n"
    with pytest.raises(CsvImportError) as exc:
        rows_to_profile(rows(bad), META)
    assert exc.value.problems == [
        "line 2: unit must be a number, got 'x'",
        "line 3: lemma is empty",
        "line 4: translation is empty",
        "line 5: expected 4 columns, got 2",
    ]


def test_empty_input():
    with pytest.raises(CsvImportError, match="no entries found"):
        rows_to_profile(rows("unit;lemma;info;translation\n"), META)


def _args(src, out, *extra):
    return [
        "import-csv", str(src), "-o", str(out), "--id", "test-words", "--title", "Test",
        "--source-lang", "la", "--tr-lang", "de", *extra,
    ]  # fmt: skip


def test_cli_roundtrip(tmp_path, capsys):
    src = tmp_path / "words.csv"
    src.write_text("﻿" + CSV, encoding="utf-8")  # with BOM, as Excel writes it
    out = tmp_path / "words.yaml"
    assert main(_args(src, out)) == 0
    assert "wrote 2 units, 4 entries" in capsys.readouterr().out
    text = out.read_text(encoding="utf-8")
    assert "de: [der Seemann, der Matrose]" in text
    assert validate_profile(load_profile(out)) == []
    assert main(["validate", str(out)]) == 0


def test_cli_refuses_to_overwrite(tmp_path, capsys):
    src = tmp_path / "words.csv"
    src.write_text(CSV, encoding="utf-8")
    out = tmp_path / "words.yaml"
    out.write_text("keep me", encoding="utf-8")
    assert main(_args(src, out)) == 1
    assert "use --force" in capsys.readouterr().err
    assert out.read_text(encoding="utf-8") == "keep me"
    assert main(_args(src, out, "--force")) == 0


def test_cli_reports_bad_rows(tmp_path, capsys):
    src = tmp_path / "words.csv"
    src.write_text("1;;m.;Seemann\n", encoding="utf-8")
    assert main(_args(src, tmp_path / "out.yaml")) == 1
    assert "line 1: lemma is empty" in capsys.readouterr().err
    assert not (tmp_path / "out.yaml").exists()


def test_cli_rejects_invalid_metadata(tmp_path, capsys):
    src = tmp_path / "words.csv"
    src.write_text(CSV, encoding="utf-8")
    args = _args(src, tmp_path / "out.yaml")
    args[args.index("test-words")] = "Not A Slug"
    assert main(args) == 1
    assert "profile.id" in capsys.readouterr().err
