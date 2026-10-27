create or replace package wr_errors as
  -- The errors wardround raises, so callers and tests can name them.

  -- A message refers to a visit or order that hasn't arrived yet. The
  -- message is held and retried.
  waiting_for     constant pls_integer := -20001;
  -- A code the sender used has no alias. Someone has to map it.
  unmapped_code   constant pls_integer := -20002;
  -- A field is missing or can't be read.
  bad_field       constant pls_integer := -20003;
  -- The message makes no sense for the visit as it stands, such as a
  -- transfer after discharge.
  out_of_step     constant pls_integer := -20004;

  e_waiting_for    exception;
  e_unmapped_code  exception;
  e_bad_field      exception;
  e_out_of_step    exception;
  pragma exception_init(e_waiting_for, -20001);
  pragma exception_init(e_unmapped_code, -20002);
  pragma exception_init(e_bad_field, -20003);
  pragma exception_init(e_out_of_step, -20004);
end wr_errors;
/
