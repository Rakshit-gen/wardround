-- Interface status.
--
-- Requirement: for the messages each feed sent in the period, how many
-- of each type were applied, held, ignored or in error, so the
-- interface team can see a feed going wrong. A message's time is the one
-- in its MSH-7, or when it arrived if that couldn't be read.
--
-- Binds: :from_day and :to_day as YYYY-MM-DD.
select m.sending_app as feed,
       m.message_type,
       count(*) as messages,
       count(case when m.status = 'DONE' then 1 end) as done,
       count(case when m.status = 'HELD' then 1 end) as held,
       count(case when m.status = 'IGNORED' then 1 end) as ignored,
       count(case when m.status = 'ERROR' then 1 end) as errors,
       count(case when m.status = 'NEW' then 1 end) as waiting
  from hl7_messages m
 where nvl(m.event_dt, cast(m.received_at as date)) >= to_date(:from_day, 'YYYY-MM-DD')
   and nvl(m.event_dt, cast(m.received_at as date)) < to_date(:to_day, 'YYYY-MM-DD')
 group by m.sending_app, m.message_type
 order by m.sending_app, m.message_type;
