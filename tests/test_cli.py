import pytest

from wardround import cli


def test_generate_writes_one_message_per_line_with_cr_segments(tmp_path, capsys):
    out = tmp_path / "feed.hl7"
    cli.main(
        ["generate", "--days", "2", "--ed-per-day", "5", "--start", "2026-03-01", "--out", str(out)]
    )
    messages = cli.read_feed(out)
    assert messages and all(m.startswith("MSH|") for m in messages)
    assert all("\r" in m and "\n" not in m for m in messages)
    assert f"{len(messages)} messages to {out}" in capsys.readouterr().out


def test_report_renders_every_format_and_names_a_failed_report(monkeypatch, tmp_path, capsys):
    from wardround import db, reports

    def run(conn, name, from_day, to_day):
        if name == "readmissions":
            raise db.oracledb.DatabaseError("ORA-00942: table or view does not exist")
        return ["unit", "n"], [("4W", 3)]

    monkeypatch.setattr(db, "connect", lambda: None)
    monkeypatch.setattr(reports, "run", run)
    for fmt in ("text", "csv", "html"):
        out = tmp_path / f"r.{fmt}"
        with pytest.raises(SystemExit) as stopped:
            cli.main(
                [
                    "report",
                    "--from",
                    "2026-03-01",
                    "--to",
                    "2026-04-01",
                    "--format",
                    fmt,
                    "--out",
                    str(out),
                ]
            )
        assert stopped.value.code == 1
        page = out.read_text()
        assert "census" in page and "4W" in page
    assert "report readmissions failed: ORA-00942" in capsys.readouterr().err
