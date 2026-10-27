-- Nursing units: the emergency department, wards and intensive care.
-- A unit is a code value (code set 220); this adds what the reports need
-- to know about it.

create table units (
  unit_cd       number primary key constraint units_cd_fk references code_values,
  kind          varchar2(4) not null constraint units_kind_ck check (kind in ('ED', 'WARD', 'ICU')),
  staffed_beds  number not null constraint units_beds_ck check (staffed_beds > 0)
);
