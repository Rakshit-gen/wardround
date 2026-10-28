"""Against a wardround database: set WARDROUND_DSN (CI does). The feed is
for 2030, so it stays out of the reports for the main CI feed."""

import os
import threading
from datetime import datetime

import pytest

from wardround import db, hl7, mllp, reports
from wardround.feed import Feed

pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(not os.environ.get("WARDROUND_DSN"), reason="WARDROUND_DSN isn't set"),
]


@pytest.fixture(scope="module")
def loaded():
    """A two-day feed sent over MLLP through a listener and applied."""
    conn = db.connect()
    feed = Feed(seed=7, start=datetime(2030, 1, 1), days=2, ed_per_day=15, direct_per_day=1)
    srv = mllp.server("127.0.0.1", 0, lambda raw: db.receive(conn, raw))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        with mllp.Sender("127.0.0.1", srv.server_address[1]) as sender:
            acks = [sender.send(o.raw) for o in feed.messages()]
    finally:
        srv.shutdown()
        srv.server_close()
    db.process(conn)
    yield conn, feed, acks
    conn.close()


def test_every_message_is_accepted(loaded):
    _, feed, acks = loaded
    assert len(acks) == len(feed.messages())
    assert {hl7.ack_code(a) for a in acks} == {"AA"}


def test_a_resend_gets_the_same_ack_control_id(loaded):
    _, feed, acks = loaded
    by_control = {}
    for o, ack in zip(feed.messages(), acks, strict=True):
        key = (o.source, hl7.fields_of(o.raw, "MSH")[10])
        by_control.setdefault(key, set()).add(hl7.fields_of(ack, "MSH")[10])
    assert all(len(ids) == 1 for ids in by_control.values())


def test_nothing_is_left_new_and_held_messages_are_explained(loaded):
    conn, _, _ = loaded
    with conn.cursor() as cur:
        cur.execute("""select count(*) from hl7_messages
                        where event_dt >= date '2030-01-01'
                          and (status = 'NEW' or status in ('HELD', 'ERROR') and error is null)""")
        assert cur.fetchone()[0] == 0


def test_errors_are_only_the_defects_sent_on_purpose(loaded):
    conn, _, _ = loaded
    with conn.cursor() as cur:
        cur.execute("""select error from hl7_messages
                        where status = 'ERROR' and event_dt >= date '2030-01-01'""")
        for (error,) in cur:
            assert '"4WEST"' in error or '"2093-3"' in error, error


@pytest.mark.parametrize("name", reports.NAMES)
def test_every_report_runs(loaded, name):
    conn, _, _ = loaded
    columns, rows = reports.run(conn, name, "2030-01-01", "2030-01-03")
    assert columns
    if name in ("census", "interface", "lab_turnaround", "ed_throughput"):
        assert rows


def test_python_escaping_is_what_the_plsql_reader_unescapes(loaded):
    conn, _, _ = loaded
    family = "D'SOUZA^ & O|BRIEN~\\"
    raw = hl7.message(
        hl7.msh("REG", "ADT^A04^ADT_A01", datetime(2030, 2, 1, 9), "ESC1"),
        hl7.segment("EVN", {1: "A04", 2: "20300201090000"}),
        hl7.segment("PID", {1: "1", 3: "ESCM1^^^HOSP^MR", 5: hl7.escape(family) + "^ANA"}),
        hl7.segment("PV1", {1: "1", 2: "E", 3: "ED^^", 19: "ESCF1"}),
    )
    assert hl7.ack_code(db.receive(conn, raw)) == "AA"
    db.process(conn)
    with conn.cursor() as cur:
        cur.execute("select family_name, given_name from persons where mrn = 'ESCM1'")
        assert cur.fetchone() == (family, "ANA")
