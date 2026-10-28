# Design

## Data model

The tables follow the shape most hospital systems share: a patient has
visits, a visit has a location history, orders and results, and every
coded value is a row in a code set rather than a string.

```
code_sets ─< code_values ─< code_value_aliases      (what each feed calls a value)
                 │
persons ─< encounters ─< encounter_locations >── units
               │   └──< diagnoses
               └──< orders ─< clinical_events       (versions of each result)
                      └── tat_targets (by test and priority)

hl7_messages                                        (every message, as received)
```

- **Code sets.** Visit types (71), dispositions (19), nursing units
  (220), orderable tests (200) and result codes (72). A value has a
  `meaning`, which code refers to (`codes.cd(220, '4W')`), and a
  `display`. Feeds never send code values: they send their own codes,
  and `code_value_aliases` maps each feed's code to a value. A code
  with no alias fails the message instead of being guessed.
- **Encounters.** One row per visit, keyed by the visit number (FIN)
  registration sends in PV1-19. An emergency visit that's admitted
  stays one visit: `arrive_dt` is when the patient came to the ED and
  `inpatient_dt` when they were admitted, which is what length of stay
  is measured from.
- **Location history.** `encounter_locations` has a row per stretch the
  patient spent in one bed, from `beg_dt` to `end_dt` (open while they
  are still there). Census, ED time and boarding all come from it.
- **Results.** `clinical_events` keeps every version of a result:
  preliminary, final, corrections. A new version closes the one before
  it (`valid_until`), and a unique index on the open versions makes
  sure there's only one current result per order and code. The
  `current_results` view is what a clinician would see.
- **Messages.** `hl7_messages` stores each message as received, with its
  status (NEW, DONE, HELD, ERROR, IGNORED) and the reason when it isn't
  DONE. It's both the queue and the audit trail.

## How a message goes in

```
feed ──MLLP──> listener ──> inbound.receive ──> hl7_messages (NEW) ──> commit ──> ACK
                                                     │
                            inbound.process  <───────┘
                              ├─ adt.apply_message      ADT^A01 A02 A03 A04 A06 A08 A11 A13
                              ├─ lab.apply_order        ORM^O01
                              └─ lab.apply_results      ORU^R01
```

Receiving and applying are separate on purpose. `receive` only parses
MSH, stores the message and returns the ACK; the listener commits
before it sends the ACK, so a message the feed was told we have is in
the database whatever happens next. A resend (same sender and control
id) isn't stored again and gets the same ACK. Something that isn't HL7
gets AR and isn't stored.

`process` applies new messages in the order they arrived, each under a
savepoint, so a message goes in completely or not at all. What happens
then:

- **DONE**: applied.
- **HELD**: it needs something that hasn't arrived, such as results
  for an order the order entry system hasn't sent yet, or a transfer
  for a visit registration hasn't registered. After the new messages,
  `process` retries held ones for as long as that applies any of them.
- **ERROR**: something about the message is wrong: a code nobody
  mapped, a discharge before the patient's last move, results for a
  cancelled order. The reason is stored, the next message goes on, and
  once the cause is fixed (`codes.map_alias`, say) `inbound.reprocess`
  puts it back in the queue.
- **IGNORED**: a message type wardround doesn't use, such as SIU.

## Messages that arrive out of order

Feeds don't send in event order: interfaces queue, retry and restart.
The ADT and lab code is written so the final state depends on the
events, not on the order they arrived in.

- **Transfers** go in by their event time (EVN-6, else EVN-2, else
  MSH-7). `adt.move` finds the stretch of location history the event
  time falls in and splits it there; the new stretch runs to where the
  old one ended. A transfer at 12:00 that arrives after one at 14:00
  ends up between the admission and the 14:00 move.
- **Resends** change nothing: moving a patient to the bed they're in,
  registering a visit that exists or placing an order that exists is a
  no-op.
- **Results** are versioned by the time they were reported (OBR-22). A
  result reported before the version already stored is ignored, which
  covers a preliminary result arriving after the final one and a failed
  message reprocessed after a correction came.
- **Dependencies** wait: results before their order, an order before
  its visit's registration, a transfer before the registration. All are
  HELD and applied when what they need comes.

## Reading HL7

`hl7.parse` splits a message into segments on CR, LF or CRLF, and reads
the separators from MSH-1 and MSH-2 instead of assuming `|^~\&`. Fields
are numbered the way the standard numbers them, which is the main thing
to get right: PID-3 is the third field after `PID`, but in MSH the
field separator is itself MSH-1, so MSH-3 is the second field after
`MSH`. `hl7.get` takes field, component, repetition and subcomponent
numbers, unescapes the value (`\F\` `\S\` `\T\` `\R\` `\E\` `\.br\`),
and returns null for `""`, which HL7 uses to say a value was deleted.
Python's `wardround.hl7` builds messages with the same numbering, and a
database test checks a name escaped in Python comes out of the PL/SQL
reader unchanged.

Fields used:

| Message | Fields |
|---|---|
| all | MSH-3 sender, MSH-7 time, MSH-9 type, MSH-10 control id |
| ADT | EVN-2, EVN-6 event time; PID-3 MRN (the repetition with type MR), PID-5 name, PID-7 birth date, PID-8 sex; PV1-2 class, PV1-3 unit, room, bed; PV1-19 visit number; PV1-36 disposition; PV1-44 arrival, PV1-45 discharge; DG1-3 diagnosis, DG1-15 rank |
| ORM | ORC-1 NW or CA, ORC-2 placer number, ORC-9 order time; OBR-4 test, OBR-27.6 priority |
| ORU | OBR-2 placer number, OBR-7 collected, OBR-22 reported; OBX-3 code, OBX-5 value, OBX-6 units, OBX-7 range, OBX-8 flag, OBX-11 status, OBX-14 observed |
