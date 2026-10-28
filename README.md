# wardround

Hospital reporting in Oracle PL/SQL and Python. HL7 v2 messages come in
over MLLP from registration, order entry and the lab: admissions,
transfers, discharges, lab orders and results. They're stored and
acknowledged, then applied to a patient and visit model in PL/SQL, which
copes with messages that arrive out of order, twice, or before what they
depend on. Out of it come the reports a hospital runs every morning:
midnight census and occupancy, length of stay, 30-day readmissions, ED
throughput and boarding, lab turnaround against targets, and the state
of the interfaces.

All patient data here is synthetic, made by the generator in this repo.

`docs/design.md` has the data model, how messages are applied and what
each report counts; `docs/runbook.md` what to do about held and failed
messages; `docs/rca.md` the root cause analyses of problems found while
building it; `CHANGELOG.md` what's in each release.

## How it works

```
REG (ADT)  ─┐
CPOE (ORM) ─┼─ MLLP ─> wardround listen ─> inbound.receive ─> hl7_messages ─> commit ─> ACK
LAB (ORU)  ─┘                                                     │
                                       inbound.process <──────────┘
                                         adt.apply_message   visits, location history, diagnoses
                                         lab.apply_order     orders
                                         lab.apply_results   versioned results
                                                                  │
                                       reports/*.sql <────────────┘   wardround report, or SQL*Plus
```

- A message is stored and committed before it's acknowledged, so
  nothing the feed was told we have is lost. A resend gets the same ACK
  and isn't stored twice.
- Messages are applied as of their own event times. A transfer that
  arrives after a later one still goes in the right place in the
  location history; a preliminary result that turns up after the final
  one is ignored.
- A message waiting for another (results before their order, a transfer
  before the registration) is HELD and goes in when the other arrives.
  One that's wrong (a code nobody mapped) is ERROR with the reason, and
  can be reprocessed once it's fixed.
- Every code a feed sends is mapped through `code_value_aliases` to a
  code value; an unmapped one fails the message rather than being
  guessed.

## Running it

Needs an Oracle database (19c or later; CI uses 23ai Free) and Python
3.10 or later.

```
docker run -d --name oracledb -p 1521:1521 -e ORACLE_PASSWORD=wardround \
  -e APP_USER=wardround -e APP_USER_PASSWORD=wardround gvenzl/oracle-free:23
RUNTIME=docker ./scripts/ci.sh        # installs utPLSQL and wardround, runs the tests

pip install -e ".[dev]"
export WARDROUND_DSN=localhost/FREEPDB1
wardround generate --out build/feed.hl7          # 45 days from 15 Feb 2026
wardround listen &                               # MLLP on port 2575
wardround send build/feed.hl7
wardround process
wardround report --from 2026-03-01 --to 2026-04-01
```

`scripts/pipeline.sh` does the last five steps and then fixes the
feed's unmapped codes:

```
wardround map 72 LAB 2093-3 CHOL --display Cholesterol
wardround map 220 REG 4WEST 4W
wardround reprocess
```

The same reports run from SQL*Plus:

```
sqlplus wardround/wardround@//localhost/FREEPDB1 @reports/run.sql 2026-03-01 2026-04-01
```

`wardround report --format html --out reports.html` writes them as one
page, and `--format csv` as CSV.
