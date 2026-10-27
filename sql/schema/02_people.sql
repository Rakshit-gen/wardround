-- Patients. The medical record number is the hospital's own id for a
-- person and stays the same across visits.

create table persons (
  person_id    number generated always as identity primary key,
  mrn          varchar2(20) not null constraint persons_mrn_uk unique,
  family_name  varchar2(60) not null,
  given_name   varchar2(60),
  birth_date   date,
  sex          varchar2(1) constraint persons_sex_ck check (sex in ('F', 'M', 'U')),
  updated_at   date default sysdate not null
);
