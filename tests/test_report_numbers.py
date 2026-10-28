"""The reports' numbers for a handful of patients small enough to work out
by hand. In May 2031, so nothing else in the database is in the period,
except patients from other feeds who were never discharged: those are
in every census, so the census is compared before and after.

  A  ED 1 May 20:00, admitted 23:00 while still in the ED, to 4W 2 May
     02:00, home 3 May 10:00. Back on 10 May and admitted again: a
     readmission. A stat troponin ordered 20:30, resulted 21:20.
  B  ED 2 May 09:00 to 13:00, home, not admitted.
  C  Admitted straight to 5E 1 May 08:00, died 2 May 08:00. A routine
     CBC ordered 09:00, resulted 13:30, past its four hours.
"""

import os
from datetime import datetime
from itertools import count

import pytest

from wardround import db, hl7, reports

pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(not os.environ.get("WARDROUND_DSN"), reason="WARDROUND_DSN isn't set"),
]

FROM, TO = "2031-05-01", "2031-05-04"
_ids = count(1)


def t(day: int, hour: int, minute: int = 0) -> datetime:
    return datetime(2031, 5, day, hour, minute)


def adt(event, fin, mrn, at, unit, patient_class="E", disp=""):
    return hl7.message(
        hl7.msh("REG", f"ADT^{event}^ADT_A01", at, f"N31{next(_ids)}"),
        hl7.segment("EVN", {1: event, 2: hl7.ts(at)}),
        hl7.segment("PID", {1: "1", 3: f"{mrn}^^^HOSP^MR", 5: "TEST^PATIENT", 8: "F"}),
        hl7.segment("PV1", {1: "1", 2: patient_class, 3: f"{unit}^1^A", 19: fin, 36: disp}),
    )


def lab(fin, placer, test, loinc, ordered, reported, stat):
    order = hl7.message(
        hl7.msh("CPOE", "ORM^O01^ORM_O01", ordered, f"N31{next(_ids)}"),
        hl7.segment("PV1", {1: "1", 19: fin}),
        hl7.segment("ORC", {1: "NW", 2: placer, 9: hl7.ts(ordered)}),
        hl7.segment("OBR", {1: "1", 2: placer, 4: test, 27: "^^^^^" + ("S" if stat else "R")}),
    )
    result = hl7.message(
        hl7.msh("LAB", "ORU^R01^ORU_R01", reported, f"N31{next(_ids)}"),
        hl7.segment("PV1", {1: "1", 19: fin}),
        hl7.segment("OBR", {1: "1", 2: placer, 7: hl7.ts(ordered), 22: hl7.ts(reported)}),
        hl7.segment("OBX", {1: "1", 2: "NM", 3: f"{loinc}^^LN", 5: "1", 11: "F"}),
    )
    return [order, result]


SCENARIO = [
    adt("A01", "N31C", "N31MC", t(1, 8), "5E", "I"),
    *lab("N31C", "N31P2", "CBC", "6690-2", t(1, 9), t(1, 13, 30), stat=False),
    adt("A04", "N31A1", "N31MA", t(1, 20), "ED"),
    *lab("N31A1", "N31P1", "TROP", "10839-9", t(1, 20, 30), t(1, 21, 20), stat=True),
    adt("A01", "N31A1", "N31MA", t(1, 23), "ED"),
    adt("A02", "N31A1", "N31MA", t(2, 2), "4W"),
    adt("A03", "N31C", "N31MC", t(2, 8), "5E", disp="20"),
    adt("A04", "N31B", "N31MB", t(2, 9), "ED"),
    adt("A03", "N31B", "N31MB", t(2, 13), "ED", disp="01"),
    adt("A03", "N31A1", "N31MA", t(3, 10), "4W", disp="01"),
    adt("A04", "N31A2", "N31MA", t(10, 8), "ED"),
    adt("A01", "N31A2", "N31MA", t(10, 9), "ED"),
]


def rows_by_first_column(conn, name):
    columns, rows = reports.run(conn, name, FROM, TO)
    return {row[0]: dict(zip(columns, row, strict=True)) for row in rows}


@pytest.fixture(scope="module")
def loaded():
    """The connection, and the census before the scenario went in."""
    conn = db.connect()
    census_before = rows_by_first_column(conn, "census")
    for raw in SCENARIO:
        assert hl7.ack_code(db.receive(conn, raw)) == "AA"
    db.process(conn)
    with conn.cursor() as cur:
        cur.execute(
            "select count(*) from hl7_messages where control_id like 'N31%' and status <> 'DONE'"
        )
        assert cur.fetchone()[0] == 0
    yield conn, census_before
    conn.close()


@pytest.fixture
def conn(loaded):
    return loaded[0]


def test_census(loaded):
    conn, census_before = loaded
    after = rows_by_first_column(conn, "census")
    # Three midnights: 1 May nobody, 2 May A in the ED and C in 5E, 3 May A in 4W.
    for unit in ("ED", "4W", "5E"):
        before, now = census_before[unit], after[unit]
        assert now["nights"] == 3
        assert round((now["avg_census"] - before["avg_census"]) * 3) == 1, unit
    assert after["ICU"]["avg_census"] == census_before["ICU"]["avg_census"]


def test_length_of_stay_runs_from_admission_not_arrival(conn):
    los = rows_by_first_column(conn, "length_of_stay")
    assert los["4W"]["discharges"] == 1
    assert los["4W"]["mean_days"] == 1.46  # 1 May 23:00 to 3 May 10:00
    assert los["5E"]["mean_days"] == 1.0
    assert los["ALL"]["discharges"] == 2
    assert los["ALL"]["mean_days"] == 1.23


def test_readmissions_leave_out_patients_who_died(conn):
    re = rows_by_first_column(conn, "readmissions")
    assert re["ALL"] == {"disposition": "ALL", "stays": 1, "readmitted": 1, "rate_pct": 100}
    assert "EXPIRED" not in re


def test_ed_time_and_boarding(conn):
    ed = rows_by_first_column(conn, "ed_throughput")
    assert ed["ADMITTED"]["visits"] == 1
    assert ed["ADMITTED"]["median_ed_hours"] == 6
    assert ed["ADMITTED"]["median_boarding_hours"] == 3
    assert ed["NOT_ADMITTED"]["median_ed_hours"] == 4
    assert ed["ALL"]["visits"] == 2
    assert ed["ALL"]["boarded_over_4h"] == 0


def test_lab_turnaround_against_targets(conn):
    columns, rows = reports.run(conn, "lab_turnaround", FROM, TO)
    tat = {(r[0], r[1]): dict(zip(columns, r, strict=True)) for r in rows}
    assert tat[("TROP", "STAT")]["median_min"] == 50
    assert tat[("TROP", "STAT")]["within_target_pct"] == 100
    assert tat[("CBC", "ROUTINE")]["median_min"] == 270
    assert tat[("CBC", "ROUTINE")]["within_target_pct"] == 0
