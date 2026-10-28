# Changelog

## Unreleased

- `lab` looks up a result's current version through the expressions of
  `clinical_events_current_uk`, so it's a unique key lookup and not a
  full scan of the results table. Three times the default feed now
  applies at 1,953 messages/s instead of 670 to 894.
- A bench workflow runs the whole path at one, three and nine times the
  default feed on every push to main, each size on a fresh schema, and
  prints the slowest statements and the plan of the slowest SQL.
- `bench/python.py` times feed generation, reading a field and MLLP
  unframing, in both Python jobs.
- `wardround report --repeat`, with `--timing` giving the median,
  fastest and slowest run.
- `scripts/install.sh` split out of `ci.sh`, and `make bench` and
  `make bench-python`.

## 1.0.0

First release.

- Schema for patients, visits, location history, diagnoses, lab orders,
  versioned results and code sets with per-feed aliases, plus the
  `current_results` view.
- PL/SQL: an HL7 v2 reader (`hl7`), ADT A01 A02 A03 A04 A06 A08 A11
  A13 (`adt`), ORM and ORU (`lab`), and a message queue that stores and
  acknowledges first and applies after, holding messages that wait on
  others and keeping the reason for those that fail (`inbound`).
  `codes.map_alias` and `inbound.reprocess` for fixing failed
  messages, `inbound.purge_applied` for housekeeping.
- Eight reports as plain SQL: midnight census, length of stay, 30-day
  readmissions, ED throughput and boarding, lab turnaround and overdue
  orders against targets, interface status and errors.
- Python: a seeded synthetic feed with defects on purpose, MLLP sender
  and listener, and the `wardround` command (generate, send, listen,
  process, status, map, reprocess, report as text, CSV or HTML).
- CI on Oracle Database 23ai Free: utPLSQL tests with coverage,
  compiler warnings, the whole pipeline over MLLP, the reports from
  Python and SQL*Plus, and Python tests against the database.
