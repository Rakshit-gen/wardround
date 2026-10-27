-- Diagnoses coded on a visit, from the DG1 segments of ADT messages.
-- The ICD-10 code is kept as sent; seq is the order the sender gave.

create table diagnoses (
  encntr_id    number not null constraint diagnoses_encntr_fk references encounters,
  seq          number not null,
  icd10        varchar2(8) not null,
  description  varchar2(200),
  kind         varchar2(9) not null constraint diagnoses_kind_ck check (kind in ('PRINCIPAL', 'SECONDARY')),
  constraint diagnoses_pk primary key (encntr_id, seq)
);

create index diagnoses_icd10_ix on diagnoses (icd10);
