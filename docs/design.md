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
