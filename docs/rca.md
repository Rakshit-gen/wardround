# Root cause analyses

Problems found while building and benchmarking wardround, written up
the way they were worked out. Run ids are GitHub Actions runs of this
repository; the error text is copied from their logs. Where a problem
was found by reading the code rather than in CI, the write-up says so.

## 1. The ED report failed with ORA-00934

**Symptom.** In run 40685293743 the PL/SQL tests passed and the feed
loaded, then `wardround report` died with

```
oracledb.exceptions.DatabaseError: ORA-00934: group function is not allowed here
```

and a Python traceback that didn't say which of the seven reports it
was running.

**Narrowing it down.** Rather than guess, the report command was changed
to catch the error per report, name it, and run the rest (commit
7981812). Run 40685655874 then printed one line:

```
report ed_throughput failed: ORA-00934: group function is not allowed here
```

so the other six were fine.

**Cause.** The end of the ED query was

```sql
select case when grouping(outcome) = 1 then 'ALL' else outcome end as outcome,
       ...
 group by rollup(outcome)
 order by grouping(outcome), outcome;
```

`outcome` is both a column of the inner query and the alias of the
first output column. In ORDER BY, Oracle resolves a name to a select
list alias before a column, so `grouping(outcome)` there meant
`grouping(case when grouping(outcome) = 1 ...)`: a group function
inside a group function. The length of stay and readmission reports
use the same ROLLUP pattern but alias the output differently (`unit`
over `cv.meaning`), which is why they worked.

**Fix.** The inner column is now `kind` and only the output is called
`outcome` (commit 3a051be). Run 40685943178 ran all seven reports.

**Lesson.** With ROLLUP and an ORDER BY on `grouping()`, keep output
aliases different from the grouped column names.

## 2. The first install didn't get past the tables

Docker isn't available on the machine wardround was written on, so CI
was the first place any of the SQL ran. It failed three ways in a row.

**ORA-03050, run 40684893785.** `hl7_messages` had a column called
`raw` for the message text:

```
  raw		clob not null,
  *
ERROR at line 8:
ORA-03050: invalid identifier: "RAW" is a reserved word
```

It became `body` (commit 1af5351).

**Ten compile errors, run 40685095020.** Two causes:

```
PACKAGE BODY ADT     153  12  PLS-00204: function or pseudo-column 'DECODE' may be used inside a SQL statement only
PACKAGE BODY INBOUND  90  39  PLS-00231: function 'REASON' may not be used in SQL
```

`DECODE` had been used in PL/SQL `if` conditions, in `adt.move` and
`lab.apply_result`, to compare values that can both be null. It only
exists in SQL, so those became `a = b or a is null and b is null`.
`inbound.apply_one` set `error = reason` in an UPDATE, where `reason`
is a function private to the package body; SQL can only call
functions declared in a package spec. The error text is now read into
a variable first (commit 100a8a6). Run 40685293743 compiled everything
and passed all 50 tests that existed then.

**PLW-06010, run 40685943178.** With every warning turned on,
`sql/lint.sql` reported `keyword "BODY" used as a defined name`. The
column became `hl7_text` (commit b772007), and the lint step now fails
CI on any warning that isn't on its accepted list. That caught the
next one at once: `inbound.purge` in run 40687753174, renamed
`purge_applied` (commit 785c14f).

**Lesson.** Names to keep away from in Oracle include RAW, BODY and
PURGE. Turning all PL/SQL warnings on in CI catches the ones the
compiler accepts but flags.

## 3. Two feeds in one database looked like resends

**Found by reading the code**, before the first push, while writing
the Python database tests.

**Symptom it would have caused.** The CI pipeline loads a 2026 feed, and
the Python database tests then load a 2030 feed into the same schema.
Both feeds numbered things from 1: control ids `REG00000001`, visits
`F0000001`, orders `P00000001`. `inbound.receive` treats a repeated
sender and control id as a resend, so most of the 2030 messages would
have been acknowledged and not stored. The few that were stored would
have attached to 2026 visits with the same visit number.

**Fix.** Every number the generator makes up now carries a tag built
from the seed and the start date (commit a2b7fa0), and
`tests/test_feed.py` checks that two feeds share no numbers.

## 4. A reprocessed result could replace its correction

**Found by reading the code** while adding the `reprocess` command;
no CI run showed it.

**How it would happen.** A result message fails because it has a code
nobody mapped. Hours later the lab sends a correction (OBX-11 C), which
goes in. Then someone maps the code and reprocesses the failed
message. `lab.apply_result` saw a final result that differed from the
current version and stored it as a new version, closing the
correction. The patient's current result would have gone back to the
value the lab had corrected.

**Fix.** A result reported before the version already stored is
ignored, whatever its status (commit 09ca568). This takes in the
earlier rule that a late preliminary result is ignored. The utPLSQL
test `final_after_correction` sends the correction first and the final
after, and checks the correction is still current.

## 5. A date with dashes was read as 1 January

**Symptom.** Run 40688454308 failed one utPLSQL test,
`bad_time_still_stored`, which sends a message whose MSH-7 is
`2026-03-02` and expects it stored with no time:

```
Actual:  2026-01-01T00:00:00 (date) was expected to be null
66 tests, 1 failed, 0 errored, 0 disabled, 0 warning(s)
```

**Cause.** `hl7.ts` takes the leading digits (4 to 14 of them, an even
number) and then allowed anything that started with `.`, `+` or `-`
after them, meaning to skip fractions of a second and a UTC offset. In
`2026-03-02` the digits are `2026` and the rest, `-03-02`, starts
with `-`, so it was taken for an offset and the value read as the
start of 2026. A registration system sending ISO dates would have put
every visit on 1 January without an error.

**Fix.** After the digits only `.` and up to four digits, then `+` or
`-` and exactly four digits, are allowed (commit 80077c9). Anything else
raises bad_field, which `inbound.receive` turns into a null event time
and `adt` into an error on the message. The test `dashed_date` checks
it. Run 40688858961 passed all 67 tests.

## 6. Three times the feed applied at half the rate

**Symptom.** The bench workflow runs the whole path at one, three and
nine times the default feed, each on a fresh schema. In three runs
(40692176310, 40693357135, 40693357888) the middle size applied at
835, 718 and 894 messages/s, against 1,161 to 1,289 at the default
size and 1,749 to 2,643 at nine times. Three runs agreeing ruled out
a noisy runner.

**Finding the statement.** The bench was changed to flush the shared
pool before each size and print the slowest statements after applying
(commit 03b4774). Run 40694790021:

| size | executions | seconds | per execution |
|---|---:|---:|---:|
| default | 21,780 | 5.30 | 0.24 ms |
| three times | 66,406 | 48.23 | 0.73 ms |

for `select * from clinical_events where order_id = :b2 and event_cd =
:b1 and valid_until is null for update`, the lookup of a result's
current version in `lab`. At nine times it wasn't among the six
slowest. Its cost per execution grew with the table.

**What the plan says.** Printing the plan too (commit bc81102), run
40696401246:

```
|*  3 |    TABLE ACCESS FULL| CLINICAL_EVENTS |     1 |   250 |     3 (0)|
   3 - filter(("VALID_UNTIL" IS NULL AND "ORDER_ID"=:B2 AND "EVENT_CD"=:B1))
   - dynamic statistics used: dynamic sampling (level=2)
```

**Root cause.** The cursor was parsed on the first result, when
`clinical_events` was empty and a full scan cost 3. It kept that plan
while the table grew to 66,000 rows, so every result read the whole
table. `clinical_events_order_ix` would have found the few rows for
the order, and `clinical_events_current_uk` the one row, but the
optimizer had no reason to think either was cheaper than scanning
an empty table.

**Fix** (commit fa96713). The query is written in the terms of
`clinical_events_current_uk`, the `case` expressions it's built on, so
it's an equality on every column of a unique index and Oracle uses it
whatever the statistics say. It finds the same row: the index has an
entry only for the current version of a result with an order.

**Result.** Run 40696939963, three times the feed: 52,290 messages
applied in 14.37 s, 3,640 messages/s, where run 40696401246 took
74.97 s. The 67 utPLSQL tests pass (run 40696940150).

**Not explained.** Why the nine times size didn't suffer the same way
in the earlier runs. Something made Oracle parse the statement again
partway through, most likely, but nothing printed shows what. With
the fix it doesn't matter, so I left it.

**Prevention.** Every bench size starts with an empty table and a
flushed shared pool, the way a new install does, and prints its
slowest statements and the plan of the slowest SQL.
