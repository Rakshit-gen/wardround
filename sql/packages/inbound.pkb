create or replace package body inbound as

  -- An error message without its ORA- prefix.
  function reason return varchar2 is
  begin
    return substr(regexp_replace(sqlerrm, '^ORA-20[0-9]{3}: '), 1, 400);
  end reason;

  -- A timestamp, or null if it can't be read: a bad time is a reason to
  -- fail the message when it's applied, not to refuse it.
  function time_or_null(p_value varchar2) return date is
  begin
    return hl7.ts(p_value);
  exception
    when wr_errors.e_bad_field then
      return null;
  end time_or_null;

  function receive(p_raw clob) return varchar2 is
    l_msg      hl7.t_message;
    l_sender   varchar2(4000);
    l_control  varchar2(4000);
    l_type     varchar2(4000);
    l_id       hl7_messages.msg_id%type;
    l_at       date;
  begin
    begin
      l_msg := hl7.parse(p_raw);
    exception
      when wr_errors.e_bad_field then
        return hl7.ack(l_msg, 'AR', 'WR0', reason);
    end;
    l_sender := hl7.val(l_msg, 'MSH', 3);
    l_control := hl7.val(l_msg, 'MSH', 10);
    l_type := hl7.val(l_msg, 'MSH', 9, 1) || '^' || hl7.val(l_msg, 'MSH', 9, 2);
    if l_sender is null or l_control is null then
      return hl7.ack(l_msg, 'AR', 'WR0', 'MSH-3 and MSH-10 are needed');
    elsif length(l_sender) > 60 or length(l_control) > 60 or length(l_type) > 10 then
      return hl7.ack(l_msg, 'AR', 'WR0', 'MSH-3, MSH-9 or MSH-10 is too long');
    end if;

    l_at := time_or_null(hl7.val(l_msg, 'MSH', 7));
    begin
      insert into hl7_messages (sending_app, control_id, message_type, event_dt, body)
      values (l_sender, l_control, l_type, l_at, p_raw)
      returning msg_id into l_id;
    exception
      when dup_val_on_index then
        select msg_id into l_id
          from hl7_messages
         where sending_app = l_sender and control_id = l_control;
    end;
    return hl7.ack(l_msg, 'AA', 'WR' || l_id);
  end receive;

  -- Applies one message. Returns whether it was applied.
  function apply_one(p_msg_id number) return boolean is
    l_raw    clob;
    l_msg    hl7.t_message;
    l_type   varchar2(4000);
    l_event  varchar2(4000);
  begin
    select body into l_raw from hl7_messages where msg_id = p_msg_id for update;
    savepoint before_message;

    l_msg := hl7.parse(l_raw);
    l_type := hl7.val(l_msg, 'MSH', 9, 1);
    l_event := hl7.val(l_msg, 'MSH', 9, 2);
    if l_type = 'ADT' and adt.handles(l_event) then
      adt.apply_message(l_msg);
    elsif l_type = 'ORM' and l_event = 'O01' then
      lab.apply_order(l_msg);
    elsif l_type = 'ORU' and l_event = 'R01' then
      lab.apply_results(l_msg, p_msg_id);
    else
      update hl7_messages
         set status = 'IGNORED', attempts = attempts + 1, processed_at = systimestamp
       where msg_id = p_msg_id;
      return false;
    end if;

    update hl7_messages
       set status = 'DONE', error = null, attempts = attempts + 1, processed_at = systimestamp
     where msg_id = p_msg_id;
    return true;
  exception
    when wr_errors.e_waiting_for then
      rollback to before_message;
      update hl7_messages
         set status = 'HELD', error = reason, attempts = attempts + 1, processed_at = systimestamp
       where msg_id = p_msg_id;
      return false;
    -- Anything else, including a bug, stops this message and not the
    -- ones after it; the error is on the message for the interface
    -- report.
    when others then
      rollback to before_message;
      update hl7_messages
         set status = 'ERROR', error = reason, attempts = attempts + 1, processed_at = systimestamp
       where msg_id = p_msg_id;
      return false;
  end apply_one;

  function process(p_max pls_integer default 10000) return pls_integer is
    l_applied   pls_integer := 0;
    l_progress  boolean;
  begin
    -- The predicate matches hl7_messages_todo_ix, so only waiting
    -- messages are read however many are done.
    for r in (select msg_id
                from hl7_messages
               where case when status in ('NEW', 'HELD') then msg_id end is not null
                 and status = 'NEW'
               order by msg_id
               fetch first p_max rows only) loop
      if apply_one(r.msg_id) then
        l_applied := l_applied + 1;
      end if;
    end loop;

    loop
      l_progress := false;
      for r in (select msg_id
                  from hl7_messages
                 where case when status in ('NEW', 'HELD') then msg_id end is not null
                   and status = 'HELD'
                 order by msg_id) loop
        if apply_one(r.msg_id) then
          l_applied := l_applied + 1;
          l_progress := true;
        end if;
      end loop;
      exit when not l_progress;
    end loop;
    return l_applied;
  end process;

  procedure reprocess(p_msg_id number) is
  begin
    update hl7_messages
       set status = 'NEW', error = null
     where msg_id = p_msg_id and status in ('ERROR', 'HELD');
    if sql%rowcount = 0 then
      raise_application_error(wr_errors.out_of_step, 'message ' || p_msg_id || ' isn''t in error or held');
    end if;
    codes.reset;
  end reprocess;
end inbound;
/
