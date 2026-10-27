-- Every HL7 message received, kept as it arrived.
--
-- A message is stored before it's acknowledged, so a message the
-- sender saw accepted is never lost. It's then processed in the order
-- received:
--   NEW      not processed yet
--   DONE     applied
--   HELD     refers to a visit or order that hasn't arrived yet; it's
--            retried after later messages, since feeds do arrive out of
--            order
--   ERROR    can't be applied as sent (an unmapped code, a bad field);
--            someone has to fix the mapping and reprocess it
--   IGNORED  a message type wardround doesn't use
-- Senders resend messages they think were lost. The sender's control id
-- (MSH-10) is unique per sender, so a resend is recognised and gets the
-- same answer as the first copy.

create table hl7_messages (
  msg_id        number generated always as identity primary key,
  sending_app   varchar2(60) not null,
  control_id    varchar2(60) not null,
  message_type  varchar2(10) not null,
  event_dt      date,
  received_at   timestamp default systimestamp not null,
  raw           clob not null,
  status        varchar2(7) default 'NEW' not null
                constraint hl7_messages_status_ck check (status in ('NEW', 'DONE', 'HELD', 'ERROR', 'IGNORED')),
  error         varchar2(400),
  attempts      number default 0 not null,
  processed_at  timestamp,
  constraint hl7_messages_control_uk unique (sending_app, control_id)
);

-- Only the messages still to do are indexed: the others have a null key.
create index hl7_messages_todo_ix on hl7_messages (
  case when status in ('NEW', 'HELD') then msg_id end);
