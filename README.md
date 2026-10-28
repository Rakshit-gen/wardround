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

## With a real feed

The generator stands in for three hospital systems. To take a real
feed instead, point it at `wardround listen` (it speaks plain MLLP on
port 2575) and map its codes once: every unit, visit type, disposition,
test and result code it sends needs a row in `code_value_aliases` for
its sending application (MSH-3). The first messages to fail tell you
which are missing; `interface_errors` lists them, `wardround map` adds
them, and `wardround reprocess` applies what failed. `docs/runbook.md`
has the rest.

## Reports

March 2026 from the generated feed, as CI run 40688858961 printed them
before the unmapped codes were fixed:

```
census
unit  beds  nights  avg_census  peak_census  occupancy_pct
----  ----  ------  ----------  -----------  -------------
ED      30      31         6.1           10           20.4
3N      20      31         9.5           19           47.4
4W      28      31        10.2           18           36.3
5E      24      31        16.5           23             69
ICU     12      31         1.8            5           15.3

length_of_stay
unit  discharges  mean_days  median_days  p90_days
----  ----------  ---------  -----------  --------
3N            79       3.92         3.48      6.95
4W            84       3.89         3.28       6.7
5E           181        3.1         2.74      5.49
ED             3       3.64         3.28      5.07
ICU            8       2.19         2.17      2.63
ALL          355       3.46         2.99      5.87

readmissions
disposition  stays  readmitted  rate_pct
-----------  -----  ----------  --------
AMA              7           0         0
HOME           284          10       3.5
REHAB           16           0         0
SNF             33           2       6.1
ALL            340          12       3.5

ed_throughput
outcome       visits  still_in_ed  median_ed_hours  p90_ed_hours  median_boarding_hours  boarded_over_4h
------------  ------  -----------  ---------------  ------------  ---------------------  ---------------
ADMITTED         269            3              6.2            11                    1.8               59
NOT_ADMITTED     679            3              3.6           5.8                                       0
ALL              948            6              4.1           7.5                    1.8               59

lab_turnaround
test  priority  orders  median_min  p90_min  target_min  within_target_pct
----  --------  ------  ----------  -------  ----------  -----------------
BMP   STAT         947          44       67          60               83.2
BMP   ROUTINE      937         169      248         240               87.6
CBC   STAT         945          44       67          60               83.1
CBC   ROUTINE     1028         171      246         240               88.2
INR   STAT         200          47       69          60                 78
LACT  STAT         154          44       66          45               51.3
TROP  STAT         383          43       64          60               85.6

interface_errors
feed  status  reason                                     messages  example_msg_id  example
----  ------  -----------------------------------------  --------  --------------  ---------------------------------------------
LAB   ERROR   LAB code "?" isn't mapped in code set 72         13            6157  LAB code "2093-3" isn't mapped in code set 72
REG   ERROR   REG code "?" isn't mapped in code set 220         3            6364  REG code "4WEST" isn't mapped in code set 220
```

Things the numbers show that come from how the data went in:

- Three inpatients left from the ED in the length of stay report, and
  there are three REG errors: transfers to a ward the feed called
  `4WEST`, which wasn't mapped. A patient whose transfer failed never
  left the ED as far as the database knows.
- The 13 LAB errors are results with a cholesterol code nobody mapped.
  A message fails whole, so its order is left with no result.
  `lab_overdue` (in `build/reports.txt` from CI) lists 12 orders with
  no result past their target.
- Stat lactate has a 45 minute target where the other stat tests have
  60, and it's the one the lab misses most.

The rates behind these (how many are admitted, how long they stay) are
round numbers picked for the generator, not taken from any hospital.

## Measured

From CI run 40688858961, on a GitHub-hosted runner with Oracle Database
23ai Free in a container. One run, not an average.

| | |
|---|---|
| Messages generated | 17,437 (6,505 CPOE, 7,154 LAB, 3,778 REG), 175 of them resends |
| Sent over MLLP, one at a time, each committed before its ACK | 16.56 s, 1,053 messages/s, all AA |
| Applied by `inbound.process` | 17,235 in 15.03 s, 1,147 messages/s |
| Ended | 17,235 DONE, 27 ERROR (the unmapped codes), 0 HELD |
| After `map` and `reprocess` | 0 in error |
| Slowest report | `interface`, 0.040 s |
| utPLSQL | 67 tests, 0 failed |
| Line coverage of the PL/SQL packages | 90.5% |
| PL/SQL compiler warnings beyond the accepted list | 0 |
| Python | 43 unit tests on 3.10 and 3.13; 19 against the database |

## Tests

- **utPLSQL** (`test/`): the HL7 reader, every ADT event including
  out-of-order and resent transfers and cancellations, orders and
  versioned results, held and failed messages and reprocessing, code
  mapping. Each test sends real HL7 through `inbound.receive` and
  `inbound.process`, the path the feeds use.
- **pytest** (`tests/`): the HL7 builder, MLLP framing and the
  listener's behaviour when it can't store a message, the feed
  generator, report rendering and the CLI, without a database.
  `test_db.py` and `test_report_numbers.py` need one: the first loads a
  feed over MLLP and runs every report, the second loads three patients
  whose report numbers can be worked out by hand and checks them.
- `sql/lint.sql` recompiles the packages with every warning on; CI fails
  on any not on its short accepted list.

## Layout

```
install.sql, uninstall.sql
sql/schema/      tables and the current_results view
sql/data/        code sets, units, tests and turnaround targets
sql/packages/    hl7, codes, adt, lab, inbound, wr_errors
reports/         one SELECT per report, and run.sql for SQL*Plus
test/            utPLSQL suites
wardround/       Python: feed, hl7, mllp, db, reports, cli
tests/           pytest
scripts/         ci.sh (database and utPLSQL), pipeline.sh (feed to reports)
docs/            design, runbook, root cause analyses
```

What's left out on purpose (merges, leaves of absence, microbiology,
time zones) is at the end of `docs/design.md`.
