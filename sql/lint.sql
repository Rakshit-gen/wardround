-- Recompiles wardround's packages with every PL/SQL compiler warning on,
-- lists what the compiler says, and counts the warnings that aren't in
-- the accepted list at the bottom.
whenever sqlerror exit failure
set feedback off
set serveroutput on
set linesize 200
column name format a22
column text format a110 word_wrapped

begin
  for p in (select object_name, object_type from user_objects
             where object_type in ('PACKAGE', 'PACKAGE BODY')
               and object_name in ('WR_ERRORS', 'HL7', 'CODES', 'ADT', 'LAB', 'INBOUND')
             order by object_type, object_name) loop
    execute immediate 'alter package ' || p.object_name || ' compile '
      || case p.object_type when 'PACKAGE BODY' then 'body ' end
      || 'plsql_warnings = ''ENABLE:ALL'' reuse settings';
  end loop;
end;
/

select name, line, text
  from user_errors
 where attribute = 'WARNING'
 order by message_number, name, line;

declare
  l_n pls_integer;
begin
  select count(*) into l_n
    from user_errors
   where attribute = 'WARNING'
     and message_number not in (
       -- No AUTHID clause: definer's rights is the intent throughout.
       5018,
       -- inbound.apply_one ends WHEN OTHERS without RAISE on purpose: the
       -- error goes on the message, which is marked ERROR, and the queue
       -- goes on to the next one.
       6009);
  dbms_output.put_line(l_n || ' compiler warnings');
  if l_n > 0 then
    raise_application_error(-20999, l_n || ' compiler warnings not on the accepted list');
  end if;
end;
/
