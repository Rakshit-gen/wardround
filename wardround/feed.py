"""A synthetic hospital: ED visits, admissions, transfers, discharges and
lab work, as the HL7 messages registration (REG), order entry (CPOE) and
the lab (LAB) would send. The same seed gives the same messages.

Everything is made up. The rates are round numbers picked to give the
reports something to show, not taken from any hospital.

Some messages are sent wrong on purpose, the way feeds go wrong:
results ahead of their order, orders ahead of the registration, a
transfer sent late, a message sent twice, a unit and a result code the
code tables don't have. defects counts how many of each went out.
"""

import heapq
import math
import random
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from wardround import hl7

WARDS = ["4W", "5E", "3N"]

DISPOSITIONS = [  # UB-04 code, weight
    ("01", 72),
    ("03", 10),
    ("62", 5),
    ("02", 3),
    ("20", 3),
    ("07", 2),
]

DIAGNOSES = [
    ("I50.9", "Heart failure"),
    ("J18.9", "Pneumonia"),
    ("N39.0", "Urinary tract infection"),
    ("I21.4", "NSTEMI"),
    ("A41.9", "Sepsis"),
    ("J44.1", "COPD with exacerbation"),
    ("K35.80", "Acute appendicitis"),
    ("I48.91", "Atrial fibrillation"),
]

FAMILY = [
    "SMITH",
    "PATEL",
    "NGUYEN",
    "GARCIA",
    "KHAN",
    "OKAFOR",
    "MULLER",
    "SATO",
    "ROSSI",
    "IYER",
    "SILVA",
    "COHEN",
    "BROWN",
    "KOWALSKI",
    "HASSAN",
    "LEE",
]
GIVEN_F = ["ANA", "PRIYA", "MEI", "SARAH", "FATIMA", "GRACE", "LENA", "YUKI", "ROSA", "ZOE"]
GIVEN_M = ["JAMES", "ARJUN", "MINH", "CARLOS", "OMAR", "DAVID", "LUKAS", "KENJI", "MARCO", "TOM"]

# LOINC code, units, low, high, mean, spread, decimals
RESULTS = {
    "CBC": [
        ("6690-2", "10*3/uL", 4.0, 11.0, 8.0, 3.0, 1),
        ("718-7", "g/dL", 12.0, 16.0, 13.2, 1.8, 1),
        ("777-3", "10*3/uL", 150, 400, 250, 80, 0),
    ],
    "BMP": [
        ("2951-2", "mmol/L", 135, 145, 139, 4, 0),
        ("2823-3", "mmol/L", 3.5, 5.1, 4.2, 0.5, 1),
        ("2160-0", "mg/dL", 0.6, 1.2, 1.0, 0.4, 2),
        ("2345-7", "mg/dL", 70, 140, 115, 35, 0),
    ],
    "TROP": [("10839-9", "ng/mL", 0.0, 0.04, 0.03, 0.08, 2)],
    "LACT": [("2524-7", "mmol/L", 0.5, 2.2, 1.6, 0.9, 1)],
    "INR": [("6301-6", "", 0.8, 1.2, 1.3, 0.5, 1)],
}

# Wrong on purpose: a unit and a result code the code tables don't map.
UNMAPPED_UNIT = "4WEST"
UNMAPPED_LOINC = ("2093-3", "mg/dL", 0, 200, 190, 30, 0)  # cholesterol

RATES = {
    "admit": 0.28,
    "icu": 0.10,
    "readmit": 0.12,
    "result_before_order": 0.02,
    "order_before_registration": 0.02,
    "late_transfer": 0.05,
    "resend": 0.01,
    "unmapped_unit": 0.03,
    "unmapped_result": 0.003,
    "preliminary": 0.2,
    "correction": 0.01,
}

DEFECTS = {
    "result_before_order",
    "order_before_registration",
    "late_transfer",
    "resend",
    "unmapped_unit",
    "unmapped_result",
}


@dataclass
class Patient:
    mrn: str
    family: str
    given: str
    birth: str
    sex: str


@dataclass
class Visit:
    fin: str
    patient: Patient
    patient_class: str
    bed: str = ""


@dataclass(order=True)
class Outgoing:
    send_at: datetime
    seq: int
    source: str = field(compare=False)
    raw: str = field(compare=False)


def _lognormal(rng: random.Random, median: float, spread: float) -> float:
    return median * math.exp(rng.gauss(0, spread))


class Feed:
    def __init__(
        self,
        seed: int = 1,
        start: datetime = datetime(2026, 2, 15),
        days: int = 45,
        ed_per_day: int = 30,
        direct_per_day: int = 3,
        defects: bool = True,
    ):
        self.rng = random.Random(seed)
        # Without defects the same random numbers are drawn, so a clean
        # feed has the same patients and times as the one with defects.
        self.rates = {k: 0.0 if k in DEFECTS and not defects else v for k, v in RATES.items()}
        self.start = start
        self.end = start + timedelta(days=days)
        self.ed_per_day = ed_per_day
        self.direct_per_day = direct_per_day
        self.defects: Counter[str] = Counter()
        self._out: list[Outgoing] = []
        self._numbers: Counter[str] = Counter()
        # In every number the feed makes up, so two feeds loaded into one
        # database don't look like resends of each other.
        self.tag = f"{seed % 100:02d}{start:%y%m%d}"

    # Numbers and people

    def _next(self, kind: str) -> int:
        self._numbers[kind] += 1
        return self._numbers[kind]

    def _patient(self) -> Patient:
        sex = self.rng.choice("FM")
        birth = datetime(1935, 1, 1) + timedelta(days=self.rng.randrange(70 * 365))
        return Patient(
            mrn=f"M{self.tag}{self._next('mrn'):05d}",
            family=self.rng.choice(FAMILY),
            given=self.rng.choice(GIVEN_F if sex == "F" else GIVEN_M),
            birth=birth.strftime("%Y%m%d"),
            sex=sex,
        )

    def _visit(self, patient: Patient, patient_class: str) -> Visit:
        return Visit(f"F{self.tag}{self._next('fin'):06d}", patient, patient_class)

    # Sending

    def _send(self, source: str, at: datetime, raw: str, send_at: datetime | None = None):
        if at >= self.end:
            return
        send_at = send_at or at
        self._out.append(Outgoing(send_at, self._next("seq"), source, raw))
        if self.rng.random() < self.rates["resend"]:
            self.defects["resend"] += 1
            again = send_at + timedelta(seconds=30)
            self._out.append(Outgoing(again, self._next("seq"), source, raw))

    def _control(self, source: str) -> str:
        return f"{source}{self.tag}{self._next(source):08d}"

    def _pid(self, p: Patient) -> str:
        return hl7.segment(
            "PID",
            {1: "1", 3: f"{p.mrn}^^^HOSP^MR", 5: f"{p.family}^{p.given}", 7: p.birth, 8: p.sex},
        )

    def _adt(
        self,
        event: str,
        at: datetime,
        v: Visit,
        unit: str,
        room: str = "",
        bed: str = "",
        disp: str = "",
        diagnosis: tuple[str, str] | None = None,
        send_at: datetime | None = None,
    ) -> None:
        segs = [
            hl7.msh("REG", f"ADT^{event}^ADT_A01", at, self._control("REG")),
            hl7.segment("EVN", {1: event, 2: hl7.ts(at)}),
            self._pid(v.patient),
            hl7.segment(
                "PV1", {1: "1", 2: v.patient_class, 3: f"{unit}^{room}^{bed}", 19: v.fin, 36: disp}
            ),
        ]
        if diagnosis:
            code, text = diagnosis
            segs.append(hl7.segment("DG1", {1: "1", 3: f"{code}^{hl7.escape(text)}^I10", 15: "1"}))
        self._send("REG", at, hl7.message(*segs), send_at)

    # Lab work

    def _value(self, spec) -> tuple[str, str, str, str]:
        code, units, low, high, mean, spread, places = spec
        value = max(0.0, self.rng.gauss(mean, spread))
        if code == "10839-9" and value < 0.01:
            return code, "<0.01", units, "N"
        flag = "L" if value < low else "H" if value > high else "N"
        return code, f"{value:.{places}f}", units, flag

    def _obx(self, results, status: str) -> list[str]:
        return [
            hl7.segment(
                "OBX",
                {
                    1: str(i),
                    2: "ST" if value.startswith("<") else "NM",
                    3: f"{code}^^LN",
                    5: value,
                    6: units,
                    8: flag,
                    11: status,
                },
            )
            for i, (code, value, units, flag) in enumerate(results, 1)
        ]

    def _oru(
        self,
        v: Visit,
        placer: str,
        collected: datetime,
        reported: datetime,
        results,
        status: str,
        send_at: datetime | None = None,
    ) -> None:
        segs = [
            hl7.msh("LAB", "ORU^R01^ORU_R01", reported, self._control("LAB")),
            self._pid(v.patient),
            hl7.segment("PV1", {1: "1", 19: v.fin}),
            hl7.segment("OBR", {1: "1", 2: placer, 7: hl7.ts(collected), 22: hl7.ts(reported)}),
            *self._obx(results, status),
        ]
        self._send("LAB", reported, hl7.message(*segs), send_at)

    def _lab(self, v: Visit, test: str, ordered: datetime, stat: bool) -> None:
        """An order and its results. Stat orders are collected and run
        faster."""
        placer = f"P{self.tag}{self._next('placer'):08d}"
        collected = ordered + timedelta(
            minutes=self.rng.uniform(5, 25) if stat else self.rng.uniform(20, 120)
        )
        tat = _lognormal(self.rng, 28 if stat else 95, 0.45)
        reported = collected + timedelta(minutes=tat)

        results = [self._value(spec) for spec in RESULTS[test]]
        # Drawn whether it's sent or not, so defects don't change the
        # random numbers everything after them gets.
        extra = self._value(UNMAPPED_LOINC)
        if self.rng.random() < self.rates["unmapped_result"]:
            self.defects["unmapped_result"] += 1
            results.append(extra)

        order_sent = None
        if self.rng.random() < self.rates["result_before_order"] and reported < self.end:
            self.defects["result_before_order"] += 1
            order_sent = reported + timedelta(minutes=1)
        orc = hl7.segment("ORC", {1: "NW", 2: placer, 9: hl7.ts(ordered)})
        obr = hl7.segment("OBR", {1: "1", 2: placer, 4: test, 27: "^^^^^" + ("S" if stat else "R")})
        self._send(
            "CPOE",
            ordered,
            hl7.message(
                hl7.msh("CPOE", "ORM^O01^ORM_O01", ordered, self._control("CPOE")),
                self._pid(v.patient),
                hl7.segment("PV1", {1: "1", 19: v.fin}),
                orc,
                obr,
            ),
            order_sent,
        )

        if test == "CBC" and self.rng.random() < self.rates["preliminary"]:
            self._oru(v, placer, collected, collected + timedelta(minutes=tat * 0.6), results, "P")
        self._oru(v, placer, collected, reported, results, "F")
        if self.rng.random() < self.rates["correction"]:
            fixed = [self._value(spec) for spec in RESULTS[test]]
            self._oru(
                v, placer, collected, reported + timedelta(hours=self.rng.uniform(2, 6)), fixed, "C"
            )

    # Visits

    def _transfer(self, v: Visit, at: datetime, unit: str) -> None:
        if unit == "4W" and self.rng.random() < self.rates["unmapped_unit"]:
            self.defects["unmapped_unit"] += 1
            unit = UNMAPPED_UNIT
        send_at = None
        delay = timedelta(hours=self.rng.uniform(1, 3))
        if self.rng.random() < self.rates["late_transfer"]:
            self.defects["late_transfer"] += 1
            send_at = at + delay
        self._adt("A02", at, v, unit, str(self.rng.randint(1, 40)), "A", send_at=send_at)

    def _inpatient(
        self, v: Visit, admitted: datetime, bed_at: datetime, ward: str
    ) -> datetime | None:
        """The stay from getting a bed to discharge. Returns the discharge
        time if the patient went home or to care, so could come back."""
        stay = timedelta(days=_lognormal(self.rng, 3.2, 0.6))
        discharge = bed_at + stay
        if self.rng.random() < self.rates["icu"]:
            self._transfer(v, bed_at, "ICU")
            ward_at = bed_at + timedelta(hours=self.rng.uniform(24, 72))
            if ward_at < discharge - timedelta(hours=6):
                self._transfer(v, ward_at, ward)
        else:
            self._transfer(v, bed_at, ward)

        # Bloods every morning at six while the patient is in.
        day = (admitted + timedelta(days=1)).replace(hour=6, minute=0, second=0)
        while day < discharge:
            for test in ("CBC", "BMP"):
                self._lab(v, test, day + timedelta(minutes=self.rng.uniform(0, 40)), stat=False)
            day += timedelta(days=1)

        disp = self.rng.choices([d for d, _ in DISPOSITIONS], [w for _, w in DISPOSITIONS])[0]
        self._adt("A03", discharge, v, ward, disp=disp, diagnosis=self.rng.choice(DIAGNOSES))
        return discharge if disp in ("01", "03", "62") else None

    def _ed_visit(self, patient: Patient, arrive: datetime, admit: bool) -> datetime | None:
        """An ED visit, admitted or not. Returns the discharge time of an
        admitted patient who went home or to care, who could come back."""
        v = self._visit(patient, "E")
        tests = [("CBC", True), ("BMP", True)]
        tests += [
            (t, True)
            for t, p in (("TROP", 0.4), ("LACT", 0.15), ("INR", 0.2))
            if self.rng.random() < p
        ]
        first_order = arrive + timedelta(minutes=self.rng.uniform(10, 45))

        registered_at = None
        if self.rng.random() < self.rates["order_before_registration"]:
            self.defects["order_before_registration"] += 1
            registered_at = first_order + timedelta(minutes=2)
        v.bed = str(self.rng.randint(1, 30))
        self._adt("A04", arrive, v, "ED", "BAY", v.bed, send_at=registered_at)
        for test, stat in tests:
            self._lab(v, test, first_order, stat)

        if not admit:
            leave = arrive + timedelta(hours=_lognormal(self.rng, 3.5, 0.4))
            self._adt("A03", leave, v, "ED", disp="07" if self.rng.random() < 0.03 else "01")
            return None

        decision = arrive + timedelta(hours=self.rng.uniform(2, 6))
        v.patient_class = "I"
        # Admitted but still in the ED bay until a ward bed is free.
        self._adt("A01", decision, v, "ED", "BAY", v.bed)
        bed_at = decision + timedelta(hours=_lognormal(self.rng, 2.0, 0.8))
        return self._inpatient(v, decision, bed_at, self.rng.choice(WARDS))

    def _direct_admit(self, arrive: datetime) -> None:
        v = self._visit(self._patient(), "I")
        self._adt("A01", arrive, v, "5E", str(self.rng.randint(1, 24)), "A")
        self._lab(v, "CBC", arrive + timedelta(minutes=30), stat=False)
        discharge = arrive + timedelta(days=self.rng.uniform(1, 4))
        self._adt("A03", discharge, v, "5E", disp="01", diagnosis=("K35.80", "Acute appendicitis"))

    def messages(self) -> list[Outgoing]:
        """Every message, in the order they're sent."""
        if self._out:
            return self._out
        # (arrival, tie-break, returning patient or None for a new one)
        arrivals: list[tuple[datetime, int, Patient | None]] = []
        day = self.start
        while day < self.end:
            for _ in range(self.ed_per_day):
                arrive = day + timedelta(minutes=self.rng.uniform(0, 1440))
                arrivals.append((arrive, self._next("arrival"), None))
            for _ in range(self.direct_per_day):
                self._direct_admit(day + timedelta(hours=self.rng.uniform(7, 10)))
            day += timedelta(days=1)

        heapq.heapify(arrivals)
        while arrivals:
            arrive, _, patient = heapq.heappop(arrivals)
            # Patients who come back are admitted again: that's what makes
            # it a readmission.
            admit = patient is not None or self.rng.random() < self.rates["admit"]
            patient = patient or self._patient()
            discharge = self._ed_visit(patient, arrive, admit)
            if discharge and self.rng.random() < self.rates["readmit"]:
                back = discharge + timedelta(days=self.rng.uniform(2, 28))
                if back < self.end:
                    heapq.heappush(arrivals, (back, self._next("arrival"), patient))
        self._out.sort()
        return self._out
