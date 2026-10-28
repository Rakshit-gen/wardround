-- Interface errors.
--
-- Requirement: the reasons messages are in error or still held, most
-- common first, so whoever fixes them can start with the mapping or the
-- feed defect that blocks the most. Reasons that differ only in a code,
-- a visit or order number or a time are counted together, with one
-- message as an example.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD.
with failed as (
  select m.msg_id,
         m.sending_app,
         m.status,
         m.error,
         regexp_replace(
           regexp_replace(
             regexp_replace(m.error, '"[^"]*"', '"?"'),
             '(visit|order) [^ ]+', '\1 ?'),
           '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}', '?') as reason
    from hl7_messages m
   where m.status in ('ERROR', 'HELD')
     and nvl(m.event_dt, cast(m.received_at as date)) >= to_date(:from_day, 'YYYY-MM-DD')
     and nvl(m.event_dt, cast(m.received_at as date)) < to_date(:to_day, 'YYYY-MM-DD')
)
select sending_app as feed,
       status,
       reason,
       count(*) as messages,
       min(msg_id) as example_msg_id,
       min(error) keep (dense_rank first order by msg_id) as example
  from failed
 group by sending_app, status, reason
 order by count(*) desc, sending_app, reason;
