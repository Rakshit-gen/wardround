import re

import pytest

from wardround import reports


@pytest.mark.parametrize("name", reports.NAMES)
def test_every_report_is_one_select_with_both_binds(name):
    sql = "\n".join(line.split("--")[0] for line in reports.sql_of(name).splitlines())
    assert ";" not in sql
    assert set(re.findall(r":(\w+)", sql)) == {"from_day", "to_day"}


@pytest.mark.parametrize("name", reports.NAMES)
def test_every_report_starts_with_its_requirement(name):
    assert reports.requirement(name).count("Requirement:") == 1


def test_unknown_report():
    with pytest.raises(ValueError):
        reports.sql_of("../install")


def test_text_lines_up_columns_and_right_aligns_numbers():
    out = reports.text("LOS", ["unit", "days"], [("4W", 3.25), ("ICU", 10.0), ("ALL", None)])
    assert out == ("LOS\nunit  days\n----  ----\n4W    3.25\nICU     10\nALL\n")


def test_text_with_no_rows():
    assert reports.text("x", ["a"], []).endswith("(no rows)\n")


def test_csv():
    assert reports.to_csv(["a", "b"], [("x,y", 1.0), (None, 2.5)]) == 'a,b\n"x,y",1\n,2.5\n'


def test_html_escapes_text():
    page = reports.to_html("t", [("census", "a < b", ["unit"], [("<b>",)])])
    assert "<td>&lt;b&gt;</td>" in page
    assert "a &lt; b" in page
