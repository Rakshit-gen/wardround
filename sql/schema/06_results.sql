-- Results. A lab can send a result as preliminary, then final, then
-- correct it. Each version is a row: the newest has valid_until null,
-- and the one it replaced gets valid_until set to when it was replaced,
-- so a report can say what was on the chart at any time.

create table clinical_events (
  event_id      number generated always as identity primary key,
  encntr_id     number not null constraint clinical_events_encntr_fk references encounters,
  order_id      number constraint clinical_events_order_fk references orders,
  event_cd      number not null constraint clinical_events_cd_fk references code_values,
  result_val    varchar2(200),
  result_num    number,
  units         varchar2(20),
  normal_range  varchar2(30),
  abnormal      varchar2(2) constraint clinical_events_abnormal_ck check (abnormal in ('N', 'L', 'H', 'LL', 'HH', 'A')),
  status        varchar2(1) not null constraint clinical_events_status_ck check (status in ('P', 'F', 'C')),
  observed_dt   date not null,
  verified_dt   date,
  valid_from    date not null,
  valid_until   date,
  msg_id        number,
  constraint clinical_events_valid_ck check (valid_until >= valid_from)
);

create index clinical_events_encntr_ix on clinical_events (encntr_id, event_cd);
create index clinical_events_order_ix on clinical_events (order_id);

-- At most one current version of a result per order and code. Rows
-- whose keys are all null aren't indexed, so old versions, and results
-- with no order, don't count.
create unique index clinical_events_current_uk on clinical_events (
  case when valid_until is null and order_id is not null then order_id end,
  case when valid_until is null and order_id is not null then event_cd end);
