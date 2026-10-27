-- Installs wardround into the current schema:
--   sqlplus wardround/password@//localhost/FREEPDB1 @install.sql
-- The schema needs CREATE SESSION, TABLE, VIEW and PROCEDURE, and quota
-- on its tablespace.

whenever sqlerror exit failure rollback
set define off
set feedback off
set serveroutput on

prompt Creating tables
@@sql/schema/01_codes.sql
@@sql/schema/02_people.sql
@@sql/schema/03_units.sql
@@sql/schema/04_encounters.sql
@@sql/schema/05_orders.sql
@@sql/schema/06_results.sql
@@sql/schema/07_diagnoses.sql
@@sql/schema/08_interface.sql

prompt Compiling packages
@@sql/packages/wr_errors.pks
@@sql/packages/hl7.pks
@@sql/packages/codes.pks
@@sql/packages/adt.pks
@@sql/packages/lab.pks
@@sql/packages/inbound.pks
@@sql/packages/hl7.pkb
@@sql/packages/codes.pkb
@@sql/packages/adt.pkb
@@sql/packages/lab.pkb
@@sql/packages/inbound.pkb

prompt Loading reference data
@@sql/data/codes.sql
commit;

@@sql/check_errors.sql
prompt wardround installed
exit
