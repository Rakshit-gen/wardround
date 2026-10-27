-- Coded values. An EHR keeps most of its vocabularies (units, visit
-- types, lab tests, result codes, dispositions) in one table keyed by
-- code set, so a new value is a row, not a schema change. Each value has
-- a meaning that code can rely on, and a display for people.

create table code_sets (
  code_set     number primary key,
  name         varchar2(60) not null constraint code_sets_name_uk unique,
  description  varchar2(400)
);

create table code_values (
  code_value  number generated always as identity primary key,
  code_set    number not null constraint code_values_set_fk references code_sets,
  meaning     varchar2(30) not null,
  display     varchar2(100) not null,
  active      varchar2(1) default 'Y' not null constraint code_values_active_ck check (active in ('Y', 'N')),
  constraint code_values_meaning_uk unique (code_set, meaning)
);

-- What each sending system calls a value. HL7 feeds send their own codes
-- ("4W" for a unit, "CBC" for a test); an alias maps one source's code to
-- a code value. A code with no alias stops the message, so a new unit or
-- test shows up as an interface error instead of a wrong report.
create table code_value_aliases (
  code_set    number not null constraint code_value_aliases_set_fk references code_sets,
  source      varchar2(30) not null,
  alias       varchar2(60) not null,
  code_value  number not null constraint code_value_aliases_value_fk references code_values,
  constraint code_value_aliases_pk primary key (code_set, source, alias)
);

create index code_value_aliases_value_ix on code_value_aliases (code_value);
