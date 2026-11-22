from __future__ import annotations

import pytest
from conftest import DEMO_PROFILE, private_profiles

from capsa.cli import main
from capsa.lint import info_forms, lint_profile
from capsa.profile_io import load_profile


def codes(data) -> list[str]:
    return [i.code for i in lint_profile(data)]


def entry(data, unit_index, entry_id):
    return next(e for e in data["units"][unit_index]["entries"] if e["id"] == entry_id)


def test_demo_profile_is_lint_clean(demo):
    assert lint_profile(demo) == []


@pytest.mark.parametrize("path", private_profiles(), ids=lambda p: p.name)
def test_private_profiles_lint(path):
    # Only checks that lint runs; private profiles may legitimately carry warnings.
    assert isinstance(lint_profile(load_profile(path)), list)


def test_whitespace(demo):
    entry(demo, 0, "u1-nauta")["tr"]["de"][0] = "der Seemann "
    entry(demo, 0, "u1-ventus")["tr"]["de"][0] = "der  Wind"
    assert codes(demo) == ["whitespace", "whitespace"]


def test_matching_prefix_with_trailing_space(demo):
    demo["profile"]["matching"]["optional_articles"]["de"][0] = "der "
    issues = lint_profile(demo)
    assert [i.code for i in issues] == ["matching-space"]
    assert issues[0].path == "profile.matching.optional_articles.de[0]"


def test_duplicate_lemma_ignores_macrons_and_case(demo):
    entry(demo, 1, "u2-numquam")["lemma"] = "Īnsula"
    issues = lint_profile(demo)
    assert [i.code for i in issues] == ["duplicate-lemma"]
    assert "'u2-numquam' has the same lemma as 'u1-insula'" in issues[0].message


def test_deprecated_entries_are_ignored(demo):
    e = entry(demo, 1, "u2-numquam")
    e["lemma"] = "īnsula"
    e["deprecated"] = True
    assert lint_profile(demo) == []


def test_duplicate_and_combined_meanings(demo):
    entry(demo, 0, "u1-nauta")["tr"]["de"] = ["der Seemann", "der Seemann", "Matrose; Pirat"]
    assert codes(demo) == ["duplicate-meaning", "combined-meanings"]


def test_macron_variant_between_lemma_and_info(demo):
    entry(demo, 1, "u2-navigare")["info"] = "navigāre, nāvigō"  # same word, macron missing
    issues = lint_profile(demo)
    assert [i.code for i in issues] == ["macron-variant"]
    assert "navigāre / nāvigāre in u2-navigare" in issues[0].message


def test_macron_variant_across_entries(demo):
    entry(demo, 0, "u1-trans")["lemma"] = "lītus"
    entry(demo, 1, "u2-litus")["lemma"] = "litus"
    assert "macron-variant" in codes(demo)


def test_macron_variant_in_example_stem(demo):
    ex = entry(demo, 0, "u1-navigat")["examples"][0]
    ex["la"] = "Insula magna est."  # same form as the lemma, stem spelled without macron
    issues = lint_profile(demo)
    assert [i.code for i in issues] == ["macron-variant"]
    assert "insula / īnsula" in issues[0].message


def test_different_ending_macron_in_example_is_fine(demo):
    ex = entry(demo, 0, "u1-navigat")["examples"][0]
    ex["la"] = "Nauta in īnsulā est."  # ablative ending -ā vs. lemma īnsula
    assert lint_profile(demo) == []


def test_empty_unit(demo):
    for e in demo["units"][1]["entries"]:
        e["deprecated"] = True
    demo["units"][1]["review"] = []
    assert codes(demo) == ["empty-unit"]


@pytest.mark.parametrize(
    ("entry_", "forms"),
    [
        ({"info": "nāvigō"}, ["nāvigō"]),
        ({"info": "ferō, fers, fert"}, ["ferō", "fers", "fert"]),
        ({"info": "m."}, []),
        ({"info": "Präp. + Akk."}, []),
        ({"info": "nāvigō", "pos": "noun"}, []),
        ({"info": "dō, dedī", "pos": "verb"}, ["dō", "dedī"]),
        ({}, []),
    ],
)
def test_info_forms_match_client_heuristic(entry_, forms):
    assert info_forms(entry_) == forms


def test_cli_lint(tmp_path, capsys):
    assert main(["lint", str(DEMO_PROFILE)]) == 0
    bad = tmp_path / "p.yaml"
    bad.write_text(
        DEMO_PROFILE.read_text(encoding="utf-8").replace('"der", "die"', '"der ", "die"'),
        encoding="utf-8",
    )
    assert main(["lint", str(bad)]) == 0
    assert main(["lint", "--strict", str(bad)]) == 1
    assert "[matching-space]" in capsys.readouterr().out
