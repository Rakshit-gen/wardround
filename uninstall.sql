-- Removes everything install.sql created, data included.
set define off
set feedback off
set serveroutput on

begin
  for o in (select object_type, object_name
              from user_objects
             where object_type in ('VIEW', 'PACKAGE')
               and object_name in ('WR_ERRORS', 'HL7', 'CODES', 'ADT', 'LAB', 'INBOUND')) loop
    execute immediate 'drop ' || o.object_type || ' ' || o.object_name;
  end loop;
  -- Children before parents.
  for t in (select column_value as name
              from table(sys.odcivarchar2list(
                'HL7_MESSAGES', 'DIAGNOSES', 'CLINICAL_EVENTS', 'TAT_TARGETS', 'ORDERS',
                'ENCOUNTER_LOCATIONS', 'ENCOUNTERS', 'UNITS', 'PERSONS',
                'CODE_VALUE_ALIASES', 'CODE_VALUES', 'CODE_SETS'))) loop
    for x in (select table_name from user_tables where table_name = t.name) loop
      execute immediate 'drop table ' || x.table_name || ' purge';
    end loop;
  end loop;
end;
/
prompt wardround removed
exit
