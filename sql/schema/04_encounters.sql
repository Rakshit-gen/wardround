-- Visits and where the patient was during them.
--
-- An encounter is one visit, identified by its financial number (FIN),
-- which the registration system gives out and every later message about
-- the visit carries. An emergency visit that ends in admission stays the
-- same encounter: its type changes to inpatient and inpatient_dt records
-- when. Location history is kept as non-overlapping stretches, the last
-- one open until the patient moves or leaves.

create table encounters (
  encntr_id      number generated always as identity primary key,
  person_id      number not null constraint encounters_person_fk references persons,
  fin            varchar2(20) not null constraint encounters_fin_uk unique,
  encntr_type_cd number not null constraint encounters_type_fk references code_values,
  status         varchar2(10) default 'ACTIVE' not null
                 constraint encounters_status_ck check (status in ('ACTIVE', 'DISCHARGED', 'CANCELLED')),
  arrive_dt      date not null,
  inpatient_dt   date,
  disch_dt       date,
  disch_disp_cd  number constraint encounters_disp_fk references code_values,
  updated_at     date default sysdate not null,
  constraint encounters_inpatient_ck check (inpatient_dt >= arrive_dt),
  constraint encounters_disch_ck check (disch_dt >= arrive_dt),
  constraint encounters_discharged_ck check (
    (status = 'DISCHARGED' and disch_dt is not null)
    or (status = 'ACTIVE' and disch_dt is null)
    or status = 'CANCELLED')
);

create index encounters_person_ix on encounters (person_id, arrive_dt);
create index encounters_disch_ix on encounters (disch_dt);

create table encounter_locations (
  encntr_id  number not null constraint encounter_locations_encntr_fk references encounters,
  beg_dt     date not null,
  end_dt     date,
  unit_cd    number not null constraint encounter_locations_unit_fk references units,
  room       varchar2(10),
  bed        varchar2(10),
  constraint encounter_locations_pk primary key (encntr_id, beg_dt),
  constraint encounter_locations_range_ck check (end_dt > beg_dt)
);

create index encounter_locations_unit_ix on encounter_locations (unit_cd, beg_dt);
