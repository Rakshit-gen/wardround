"""Runs the SQL reports in reports/ and renders them as text, CSV or HTML.

Each report is one SELECT with :from_day and :to_day binds, the same file
SQL*Plus runs, so the numbers can't drift between the two."""

import csv
import html
import io
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent.parent / "reports"

NAMES = [
    "census",
    "length_of_stay",
    "readmissions",
    "ed_throughput",
    "lab_turnaround",
    "lab_overdue",
    "interface",
    "interface_errors",
]


def sql_of(name: str, directory: Path = DIRECTORY) -> str:
    """The report's SELECT, without the semicolon SQL*Plus needs."""
    if name not in NAMES:
        raise ValueError(f"no report called {name}")
    return (directory / f"{name}.sql").read_text().rstrip().removesuffix(";")


def requirement(name: str, directory: Path = DIRECTORY) -> str:
    """The comment at the top of the report: what it's for."""
    lines = []
    for line in (directory / f"{name}.sql").read_text().splitlines():
        if not line.startswith("--"):
            break
        lines.append(line.removeprefix("--").strip())
    return "\n".join(lines).strip()


def run(conn, name: str, from_day: str, to_day: str, directory: Path = DIRECTORY):
    """The report's column names and rows."""
    with conn.cursor() as cur:
        cur.execute(sql_of(name, directory), from_day=from_day, to_day=to_day)
        return [d[0].lower() for d in cur.description], cur.fetchall()


def _cell(value) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def text(title: str, columns: list[str], rows: list[tuple]) -> str:
    cells = [columns] + [[_cell(v) for v in row] for row in rows]
    widths = [max(len(r[i]) for r in cells) for i in range(len(columns))]
    # A column is right-aligned if everything in it is a number.
    numeric = [
        bool(rows) and all(v is None or isinstance(v, int | float) for v in (r[i] for r in rows))
        for i in range(len(columns))
    ]

    def line(row):
        return "  ".join(
            c.rjust(w) if n else c.ljust(w) for c, w, n in zip(row, widths, numeric, strict=True)
        ).rstrip()

    out = [title, line(columns), line(["-" * w for w in widths])]
    out += [line(r) for r in cells[1:]] or ["(no rows)"]
    return "\n".join(out) + "\n"


def to_csv(columns: list[str], rows: list[tuple]) -> str:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(columns)
    writer.writerows([[_cell(v) for v in row] for row in rows])
    return buf.getvalue()


def to_html(title: str, sections: list[tuple[str, str, list[str], list[tuple]]]) -> str:
    """One page with a table per report. sections are (name, requirement,
    columns, rows)."""
    parts = [
        "<!doctype html><html lang=en><meta charset=utf-8>",
        f"<title>{html.escape(title)}</title>",
        "<style>body{font:14px/1.45 system-ui,sans-serif;margin:24px;color:#222}"
        "table{border-collapse:collapse;margin:8px 0 28px}"
        "th,td{border-bottom:1px solid #ddd;padding:4px 10px;text-align:left}"
        "td.n{text-align:right;font-variant-numeric:tabular-nums}"
        "p{max-width:70ch;color:#555;white-space:pre-line}</style>",
        f"<h1>{html.escape(title)}</h1>",
    ]
    for name, req, columns, rows in sections:
        parts.append(f"<h2>{html.escape(name)}</h2><p>{html.escape(req)}</p><table><tr>")
        parts += [f"<th>{html.escape(c)}</th>" for c in columns]
        parts.append("</tr>")
        for row in rows:
            parts.append(
                "<tr>"
                + "".join(
                    f"<td class=n>{_cell(v)}</td>"
                    if isinstance(v, int | float)
                    else f"<td>{html.escape(_cell(v))}</td>"
                    for v in row
                )
                + "</tr>"
            )
        parts.append("</table>")
    return "\n".join(parts) + "\n"
