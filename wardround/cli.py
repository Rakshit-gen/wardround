"""wardround generate | send | listen | process | status | map | reprocess | report"""

import argparse
import sys
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

from wardround import hl7, mllp, reports
from wardround.feed import Feed


def read_feed(path: Path) -> list[str]:
    """Messages one per line, segments separated by CR as HL7 has them."""
    with open(path, newline="") as f:
        return [m for m in f.read().split("\n") if m]


def generate(args) -> None:
    feed = Feed(
        seed=args.seed,
        start=datetime.fromisoformat(args.start),
        days=args.days,
        ed_per_day=args.ed_per_day,
        direct_per_day=args.direct_per_day,
        defects=not args.clean,
    )
    messages = feed.messages()
    with open(args.out, "w", newline="") as f:
        for o in messages:
            f.write(o.raw + "\n")
    by_source = Counter(o.source for o in messages)
    print(
        f"{len(messages)} messages to {args.out}: "
        + ", ".join(f"{n} {s}" for s, n in sorted(by_source.items()))
    )
    print(
        "sent wrong on purpose: "
        + ", ".join(f"{n} {kind}" for kind, n in sorted(feed.defects.items()))
    )


def send(args) -> None:
    messages = read_feed(args.file)
    codes: Counter[str] = Counter()
    began = time.perf_counter()
    with mllp.Sender(args.host, args.port) as sender:
        for raw in messages:
            codes[hl7.ack_code(sender.send(raw)) or "none"] += 1
    secs = time.perf_counter() - began
    print(f"sent {len(messages)} messages in {secs:.2f} s, {len(messages) / secs:.0f} messages/s")
    print("ACKs: " + ", ".join(f"{n} {c}" for c, n in sorted(codes.items())))
    if set(codes) - {"AA"}:
        sys.exit(1)


def listen(args) -> None:
    from wardround import db

    conn = db.connect()
    srv = mllp.server(args.host, args.port, lambda raw: db.receive(conn, raw))
    print(f"listening on {args.host}:{srv.server_address[1]}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()


def process(args) -> None:
    from wardround import db

    conn = db.connect()
    began = time.perf_counter()
    applied = db.process(conn, args.batch)
    secs = time.perf_counter() - began
    print(f"applied {applied} messages in {secs:.2f} s, {applied / secs:.0f} messages/s")
    print("messages by status: " + ", ".join(f"{n} {s}" for s, n in db.statuses(conn).items()))


def status(args) -> None:
    from wardround import db

    counts = db.statuses(db.connect())
    for name in ("NEW", "HELD", "ERROR", "DONE", "IGNORED"):
        print(f"{name:<8}{counts.get(name, 0):>8}")
    if counts.get("HELD") or counts.get("ERROR"):
        print("see: wardround report --only interface_errors --from ... --to ...")


def map_code(args) -> None:
    from wardround import db

    db.map_alias(db.connect(), args.code_set, args.source, args.alias, args.meaning, args.display)
    print(f"{args.source} {args.alias} maps to {args.meaning} in code set {args.code_set}")


def reprocess(args) -> None:
    from wardround import db

    before, after = db.reprocess_errors(db.connect())
    print(f"reprocessed {before} messages in error; {after} still in error")


def report(args) -> None:
    from wardround import db

    conn = db.connect()
    names = args.only or reports.NAMES
    title = f"wardround, {args.from_day} to {args.to_day}"
    results, failed = [], []
    for n in names:
        try:
            began = time.perf_counter()
            results.append((n, *reports.run(conn, n, args.from_day, args.to_day)))
            if args.timing:
                print(f"{n}: {time.perf_counter() - began:.3f} s", file=sys.stderr)
        except db.oracledb.DatabaseError as e:
            print(f"report {n} failed: {e}", file=sys.stderr)
            failed.append(n)
    if args.format == "html":
        out = reports.to_html(title, [(n, reports.requirement(n), c, r) for n, c, r in results])
    elif args.format == "csv":
        out = "\n".join(f"# {n}\n" + reports.to_csv(c, r) for n, c, r in results)
    else:
        out = "\n".join(reports.text(n, c, r) for n, c, r in results)
    if args.out:
        Path(args.out).write_text(out)
    else:
        sys.stdout.write(out)
    if failed:
        sys.exit(1)


def main(argv=None) -> None:
    p = argparse.ArgumentParser(prog="wardround", description=__doc__)
    sub = p.add_subparsers(required=True)

    g = sub.add_parser("generate", help="write a synthetic HL7 feed to a file")
    g.add_argument("--seed", type=int, default=1)
    g.add_argument("--start", default="2026-02-15", help="first day, YYYY-MM-DD")
    g.add_argument("--days", type=int, default=45)
    g.add_argument("--ed-per-day", type=int, default=30)
    g.add_argument("--direct-per-day", type=int, default=3)
    g.add_argument("--clean", action="store_true", help="send nothing wrong on purpose")
    g.add_argument("--out", default="feed.hl7")
    g.set_defaults(func=generate)

    s = sub.add_parser("send", help="send a feed file to an MLLP listener")
    s.add_argument("file", type=Path)
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=2575)
    s.set_defaults(func=send)

    li = sub.add_parser("listen", help="take messages over MLLP into the database")
    li.add_argument("--host", default="127.0.0.1")
    li.add_argument("--port", type=int, default=2575)
    li.set_defaults(func=listen)

    pr = sub.add_parser("process", help="apply the messages waiting in the database")
    pr.add_argument("--batch", type=int, default=5000)
    pr.set_defaults(func=process)

    st = sub.add_parser("status", help="how many messages are in each state")
    st.set_defaults(func=status)

    m = sub.add_parser("map", help="map a code a feed sends to a code value")
    m.add_argument("code_set", type=int, help="e.g. 72 for result codes, 220 for units")
    m.add_argument("source", help="the feed: REG, CPOE or LAB")
    m.add_argument("alias", help="the code the feed sends")
    m.add_argument("meaning", help="the code value's meaning, added if it's new")
    m.add_argument("--display")
    m.set_defaults(func=map_code)

    rp = sub.add_parser("reprocess", help="apply the messages in error again")
    rp.set_defaults(func=reprocess)

    r = sub.add_parser("report", help="run the reports for a period")
    r.add_argument("--from", dest="from_day", required=True, help="YYYY-MM-DD")
    r.add_argument("--to", dest="to_day", required=True, help="YYYY-MM-DD, not included")
    r.add_argument("--only", action="append", choices=reports.NAMES)
    r.add_argument("--format", choices=["text", "csv", "html"], default="text")
    r.add_argument("--out")
    r.add_argument("--timing", action="store_true", help="print how long each report took")
    r.set_defaults(func=report)

    args = p.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
