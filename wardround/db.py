"""Calls into the wardround schema. The connection comes from
WARDROUND_DSN (like localhost/FREEPDB1), WARDROUND_USER and
WARDROUND_PASSWORD."""

import os

import oracledb


def connect() -> oracledb.Connection:
    dsn = os.environ.get("WARDROUND_DSN")
    if not dsn:
        raise SystemExit("set WARDROUND_DSN, e.g. localhost/FREEPDB1")
    return oracledb.connect(
        user=os.environ.get("WARDROUND_USER", "wardround"),
        password=os.environ.get("WARDROUND_PASSWORD", "wardround"),
        dsn=dsn,
    )


def receive(conn: oracledb.Connection, raw: str) -> str:
    """Stores a message and returns its ACK. Commits first, so a message
    that was acknowledged is in the database for good."""
    with conn.cursor() as cur:
        ack = cur.callfunc("inbound.receive", str, [raw])
    conn.commit()
    return ack


def process(conn: oracledb.Connection, batch: int = 5000) -> int:
    """Applies every new message, committing after each batch. Returns how
    many were applied."""
    applied = 0
    with conn.cursor() as cur:
        while True:
            applied += cur.callfunc("inbound.process", int, [batch])
            conn.commit()
            cur.execute("select count(*) from hl7_messages where status = 'NEW'")
            if cur.fetchone()[0] == 0:
                return applied


def statuses(conn: oracledb.Connection) -> dict[str, int]:
    with conn.cursor() as cur:
        cur.execute("select status, count(*) from hl7_messages group by status order by status")
        return dict(cur.fetchall())


def map_alias(conn: oracledb.Connection, code_set: int, source: str, alias: str,
              meaning: str, display: str | None = None) -> None:
    with conn.cursor() as cur:
        cur.callproc("codes.map_alias", [code_set, source, alias, meaning, display])
    conn.commit()


def reprocess_errors(conn: oracledb.Connection) -> tuple[int, int]:
    """Puts every message in error back in the queue and applies the
    queue. Returns how many were in error before, and after."""
    with conn.cursor() as cur:
        cur.execute("select msg_id from hl7_messages where status = 'ERROR' order by msg_id")
        ids = [r[0] for r in cur.fetchall()]
        for msg_id in ids:
            cur.callproc("inbound.reprocess", [msg_id])
        conn.commit()
    process(conn)
    return len(ids), statuses(conn).get("ERROR", 0)
