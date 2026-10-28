-- Installs the utPLSQL suites into the wardround schema, after
-- install.sql. Run them with:
--   exec ut.run('wardround')

whenever sqlerror exit failure rollback
set define off
set feedback off

prompt Compiling tests
@@test_fixture.pks
@@test_hl7.pks
@@test_adt.pks
@@test_lab.pks
@@test_inbound.pks
@@test_codes.pks
@@test_fixture.pkb
@@test_hl7.pkb
@@test_adt.pkb
@@test_lab.pkb
@@test_inbound.pkb
@@test_codes.pkb

@@../sql/check_errors.sql
prompt Tests are installed
