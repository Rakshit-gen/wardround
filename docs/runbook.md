# Interface runbook

What to do when the interface report shows messages that didn't go in.
Commands assume `WARDROUND_DSN` is set and wardround is installed.

## See what's wrong

```
wardround status
wardround report --from 2026-03-01 --to 2026-04-01 --only interface_errors
```

`interface_errors` groups reasons that differ only in a code, a visit or
order number or a time, most common first, with one message id as an
example. Look at the example in full:

```sql
select status, error, attempts, hl7_text from hl7_messages where msg_id = :id;
```

## HELD

A held message needs something that hasn't come: an order for these
results, the registration for this visit. `wardround process` retries
held messages every time it runs, so most clear on their own when the
other system catches up.

Held for hours means the other message isn't coming. Ask the sending
system's team for it by its number (the order's placer number or the
visit's FIN, both in the reason). Once it arrives the held message goes
in on the next run.

## ERROR

An error is something about the message itself. The reason says what.

| Reason | What to do |
|---|---|
| `LAB code "2093-3" isn't mapped in code set 72` | A feed sent a code nobody mapped. Find out what it means from the sending team, map it, reprocess (below). |
| `discharge at ... is before the last move` | Registration's times disagree. Ask them to correct the discharge or the transfer; the corrected message comes as a new one. |
| `order P... was cancelled` | Results for a cancelled order. Usually the order was cancelled by mistake: the lab and order entry teams agree which is right. |
| `order P... has results and can't be cancelled` | A cancel after the results. Clinical decision; nothing to reprocess. |
| `visit F... is cancelled` | A message for a visit whose admission was cancelled. Check with registration whether the cancel was right. |
| `no ... in PV1-19` and other missing fields | The sending system built a bad message. Send the example to its team. |

## Map a code and reprocess

```
wardround map 72 LAB 2093-3 CHOL --display Cholesterol   # result code
wardround map 220 REG 4WEST 4W                            # a unit's other name
wardround reprocess
wardround status
```

`map` adds the code value if the code set doesn't have it, and refuses
to move an alias that already maps somewhere else. `reprocess` puts
every message in error back in the queue and applies it; ones that fail
again go back to ERROR with their reason. Messages are applied as of
their own times, so reprocessing old messages doesn't put anything in
the wrong place, and a result reprocessed after its correction doesn't
replace it.

## Housekeeping

Applied messages aren't needed once their data is in. To delete those
older than 90 days:

```sql
exec dbms_output.put_line(inbound.purge_applied(sysdate - 90) || ' deleted')
commit;
```

Held and error messages are kept however old.
