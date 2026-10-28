create or replace package body lab as

  c_orderables  constant number := 200;
  c_events      constant number := 72;

  function source(p_msg hl7.t_message) return varchar2 is
  begin
    return hl7.val(p_msg, 'MSH', 3);
  end source;

  function visit_id(p_msg hl7.t_message) return encounters.encntr_id%type is
    l_fin  varchar2(4000) := hl7.val(p_msg, 'PV1', 19);
    l_id   encounters.encntr_id%type;
  begin
    if l_fin is null then
      raise_application_error(wr_errors.bad_field, 'no visit number in PV1-19');
    end if;
    select encntr_id into l_id from encounters where fin = l_fin;
    return l_id;
  exception
    when no_data_found then
      raise_application_error(wr_errors.waiting_for, 'visit ' || l_fin || ' isn''t registered yet');
  end visit_id;

  procedure apply_order(p_msg hl7.t_message) is
    l_control  varchar2(4000) := hl7.val(p_msg, 'ORC', 1);
    l_placer   varchar2(4000) := nvl(hl7.val(p_msg, 'ORC', 2), hl7.val(p_msg, 'OBR', 2));
    l_status   orders.status%type;
    l_encntr   orders.encntr_id%type;
    l_cd       orders.catalog_cd%type;
    l_priority orders.priority%type;
    l_at       date;
  begin
    if l_placer is null then
      raise_application_error(wr_errors.bad_field, 'no placer order number in ORC-2 or OBR-2');
    elsif length(l_placer) > 30 then
      raise_application_error(wr_errors.bad_field, 'placer order number "' || substr(l_placer, 1, 40) || '" is too long');
    end if;

    if l_control = 'NW' then
      -- Read before the insert: SQL can't take the message record.
      l_encntr := visit_id(p_msg);
      if hl7.val(p_msg, 'OBR', 4) is null then
        raise_application_error(wr_errors.bad_field, 'no test in OBR-4');
      end if;
      l_cd := codes.lookup(c_orderables, source(p_msg), hl7.val(p_msg, 'OBR', 4));
      l_priority := case hl7.val(p_msg, 'OBR', 27, 6) when 'S' then 'STAT' else 'ROUTINE' end;
      l_at := coalesce(hl7.ts(hl7.val(p_msg, 'ORC', 9)), hl7.ts(hl7.val(p_msg, 'MSH', 7)));
      insert into orders (encntr_id, placer_no, catalog_cd, priority, ordered_dt)
      select l_encntr, l_placer, l_cd, l_priority, l_at
        from dual
       where not exists (select null from orders where placer_no = l_placer);
    elsif l_control = 'CA' then
      begin
        select status into l_status from orders where placer_no = l_placer for update;
      exception
        when no_data_found then
          raise_application_error(wr_errors.waiting_for, 'order ' || l_placer || ' hasn''t arrived yet');
      end;
      if l_status = 'COMPLETED' then
        raise_application_error(wr_errors.out_of_step, 'order ' || l_placer || ' has results and can''t be cancelled');
      end if;
      update orders set status = 'CANCELLED', updated_at = sysdate where placer_no = l_placer;
    else
      raise_application_error(wr_errors.bad_field, 'order control "' || substr(l_control, 1, 10) || '" in ORC-1 isn''t handled');
    end if;
  end apply_order;

  -- The value as a number, if it's a plain one; values like "<0.01" or
  -- "see comment" are kept as text only.
  function as_number(p_value varchar2) return number is
  begin
    if regexp_like(p_value, '^[0-9]{1,13}(\.[0-9]{1,10})?$') then
      return to_number(p_value, '9999999999990.9999999999');
    end if;
    return null;
  end as_number;

  -- Applies one OBX to p_order. Returns whether the result is final.
  function apply_result(
    p_msg       hl7.t_message,
    p_seg       pls_integer,
    p_order     orders%rowtype,
    p_observed  date,
    p_reported  date,
    p_msg_id    number
  ) return boolean is
    l_code    varchar2(4000) := hl7.get(p_msg, p_seg, 3);
    l_cd      number;
    l_value   varchar2(4000) := hl7.get(p_msg, p_seg, 5);
    l_status  varchar2(4000) := nvl(hl7.get(p_msg, p_seg, 11), 'F');
    l_flag    varchar2(4000) := nvl(hl7.get(p_msg, p_seg, 8), 'N');
    l_from    date := p_reported;
    l_cur     clinical_events%rowtype;
    l_num     number := as_number(l_value);
    l_units   varchar2(20) := substr(hl7.get(p_msg, p_seg, 6), 1, 20);
    l_range   varchar2(30) := substr(hl7.get(p_msg, p_seg, 7), 1, 30);
    l_text    varchar2(200) := substr(l_value, 1, 200);
  begin
    if l_code is null then
      raise_application_error(wr_errors.bad_field, 'no result code in OBX-3');
    elsif l_status not in ('P', 'F', 'C') then
      raise_application_error(wr_errors.bad_field, 'result status "' || substr(l_status, 1, 10) || '" in OBX-11 isn''t P, F or C');
    end if;
    l_cd := codes.lookup(c_events, source(p_msg), l_code);
    -- Flags beyond these (W for worse, S for susceptible and so on) are
    -- kept as abnormal.
    if l_flag not in ('N', 'L', 'H', 'LL', 'HH', 'A') then
      l_flag := 'A';
    end if;

    begin
      select * into l_cur
        from clinical_events
       where order_id = p_order.order_id and event_cd = l_cd and valid_until is null
         for update;
      if l_cur.status = l_status
         and (l_cur.result_val = l_text or l_cur.result_val is null and l_text is null) then
        return l_status <> 'P'; -- a resend
      elsif l_status = 'P' and l_cur.status in ('F', 'C') then
        return true; -- a preliminary result overtaken by the final one
      end if;
      l_from := greatest(p_reported, l_cur.valid_from);
      update clinical_events set valid_until = l_from where event_id = l_cur.event_id;
    exception
      when no_data_found then
        null;
    end;

    insert into clinical_events (encntr_id, order_id, event_cd, result_val, result_num, units, normal_range,
                                 abnormal, status, observed_dt, verified_dt, valid_from, msg_id)
    values (p_order.encntr_id, p_order.order_id, l_cd, l_text, l_num, l_units, l_range,
            l_flag, l_status, p_observed,
            case when l_status <> 'P' then p_reported end, l_from, p_msg_id);
    return l_status <> 'P';
  end apply_result;

  procedure apply_results(p_msg hl7.t_message, p_msg_id number default null) is
    l_obr        pls_integer;
    l_end        pls_integer;
    l_placer     varchar2(4000);
    l_order      orders%rowtype;
    l_collected  date;
    l_reported   date;
    l_final      boolean;
    l_done       varchar2(1);
    l_n          pls_integer := 0;
  begin
    loop
      l_obr := hl7.find(p_msg, 'OBR', l_n + 1);
      exit when l_obr is null;
      l_n := l_n + 1;
      -- This OBR's results run to the next OBR, or the end.
      l_end := nvl(hl7.find(p_msg, 'OBR', 1, l_obr + 1) - 1, p_msg.segments.count);

      l_placer := hl7.get(p_msg, l_obr, 2);
      if l_placer is null then
        raise_application_error(wr_errors.bad_field, 'no placer order number in OBR-2 of OBR number ' || l_n);
      end if;
      begin
        select * into l_order from orders where placer_no = l_placer for update;
      exception
        when no_data_found then
          raise_application_error(wr_errors.waiting_for, 'order ' || l_placer || ' hasn''t arrived yet');
      end;
      if l_order.status = 'CANCELLED' then
        raise_application_error(wr_errors.out_of_step, 'order ' || l_placer || ' was cancelled');
      end if;

      l_collected := hl7.ts(hl7.get(p_msg, l_obr, 7));
      l_reported := coalesce(hl7.ts(hl7.get(p_msg, l_obr, 22)), hl7.ts(hl7.val(p_msg, 'MSH', 7)));
      l_final := false;
      for i in l_obr + 1 .. l_end loop
        if substr(p_msg.segments(i), 1, 4) = 'OBX' || p_msg.field_sep then
          l_final := apply_result(p_msg, i, l_order,
                                  coalesce(hl7.ts(hl7.get(p_msg, i, 14)), l_collected, l_reported),
                                  l_reported, p_msg_id)
                     or l_final;
        end if;
      end loop;

      -- SQL has no boolean before 23ai.
      l_done := case when l_final then 'Y' else 'N' end;
      update orders
         set collected_dt = coalesce(collected_dt, l_collected),
             verified_dt = case when l_done = 'Y' then coalesce(verified_dt, l_reported) else verified_dt end,
             status = case when l_done = 'Y' then 'COMPLETED' else status end,
             updated_at = sysdate
       where order_id = l_order.order_id;
    end loop;
    if l_n = 0 then
      raise_application_error(wr_errors.bad_field, 'no OBR segment');
    end if;
  end apply_results;
end lab;
/
