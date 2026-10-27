-- Lab orders, and how fast each kind should come back.
--
-- The placer order number is the ordering system's id for the order;
-- the results that come back for it quote it. collected_dt and
-- verified_dt are filled from the results: when the specimen was taken,
-- and when the first final result was signed off.

create table orders (
  order_id      number generated always as identity primary key,
  encntr_id     number not null constraint orders_encntr_fk references encounters,
  placer_no     varchar2(30) not null constraint orders_placer_uk unique,
  catalog_cd    number not null constraint orders_catalog_fk references code_values,
  priority      varchar2(7) not null constraint orders_priority_ck check (priority in ('STAT', 'ROUTINE')),
  status        varchar2(9) default 'ORDERED' not null
                constraint orders_status_ck check (status in ('ORDERED', 'CANCELLED', 'COMPLETED')),
  ordered_dt    date not null,
  collected_dt  date,
  verified_dt   date,
  updated_at    date default sysdate not null
);

create index orders_encntr_ix on orders (encntr_id);
create index orders_ordered_ix on orders (ordered_dt);

-- Turnaround targets, from order to verified result, in minutes.
create table tat_targets (
  catalog_cd  number not null constraint tat_targets_catalog_fk references code_values,
  priority    varchar2(7) not null constraint tat_targets_priority_ck check (priority in ('STAT', 'ROUTINE')),
  minutes     number not null constraint tat_targets_minutes_ck check (minutes > 0),
  constraint tat_targets_pk primary key (catalog_cd, priority)
);
