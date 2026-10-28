-- Runs every report in SQL*Plus for a period, the same SQL the Python
-- runner uses:
--   sqlplus wardround/wardround@//localhost/FREEPDB1 @reports/run.sql 2026-03-01 2026-04-01
set define on
set verify off
set feedback off
set pagesize 200
set linesize 220
set trimspool on
variable from_day varchar2(10)
variable to_day varchar2(10)
exec :from_day := '&1'
exec :to_day := '&2'

column unit format a6
column outcome format a12
column disposition format a14
column test format a6
column feed format a5
column message_type format a12
column reason format a50
column example format a60

prompt
prompt census
@@census.sql
prompt
prompt length_of_stay
@@length_of_stay.sql
prompt
prompt readmissions
@@readmissions.sql
prompt
prompt ed_throughput
@@ed_throughput.sql
prompt
prompt lab_turnaround
@@lab_turnaround.sql
prompt
prompt lab_overdue
@@lab_overdue.sql
prompt
prompt interface
@@interface.sql
prompt
prompt interface_errors
@@interface_errors.sql
exit
