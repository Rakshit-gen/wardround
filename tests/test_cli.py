from wardround import cli


def test_generate_writes_one_message_per_line_with_cr_segments(tmp_path, capsys):
    out = tmp_path / "feed.hl7"
    cli.main(["generate", "--days", "2", "--ed-per-day", "5", "--start", "2026-03-01",
              "--out", str(out)])
    messages = cli.read_feed(out)
    assert messages and all(m.startswith("MSH|") for m in messages)
    assert all("\r" in m and "\n" not in m for m in messages)
    assert f"{len(messages)} messages to {out}" in capsys.readouterr().out
