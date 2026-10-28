# Root cause analyses

Problems found while building wardround, written up the way they were
worked out. Run ids are GitHub Actions runs of this repository; the
error text is copied from their logs. Where a problem was found by
reading the code rather than in CI, the write-up says so.

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
