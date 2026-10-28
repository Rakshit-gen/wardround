create or replace package body test_inbound as

  function hm(p_hhmi varchar2) return date is
  begin
    return to_date('2026-03-02 ' || p_hhmi, 'YYYY-MM-DD HH24:MI');
  end hm;

  function ack_code(p_ack varchar2) return varchar2 is
  begin
    return hl7.val(hl7.parse(p_ack), 'MSA', 1);
  end ack_code;

  function count_of(p_control varchar2) return pls_integer is
    l_n pls_integer;
  begin
    select count(*) into l_n from hl7_messages where control_id = p_control;
    return l_n;
  end count_of;

  procedure accepted is
    l_ack  hl7.t_message := hl7.parse(inbound.receive(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'A1')));
    l_msg  hl7_messages%rowtype;
  begin
    select * into l_msg from hl7_messages where control_id = 'A1';
    ut.expect(hl7.val(l_ack, 'MSA', 1)).to_equal('AA');
    ut.expect(hl7.val(l_ack, 'MSA', 2)).to_equal('A1');
    ut.expect(hl7.val(l_ack, 'MSH', 10)).to_equal('WR' || l_msg.msg_id);
    ut.expect(l_msg.status).to_equal('NEW');
    ut.expect(l_msg.sending_app).to_equal('REG');
    ut.expect(l_msg.message_type).to_equal('ADT^A04');
    ut.expect(l_msg.event_dt).to_equal(hm('08:00'));
  end accepted;

  procedure duplicate is
    l_first   varchar2(4000) := inbound.receive(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'A1'));
    l_second  varchar2(4000) := inbound.receive(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'A1'));
  begin
    ut.expect(count_of('A1')).to_equal(1);
    ut.expect(hl7.val(hl7.parse(l_second), 'MSH', 10)).to_equal(hl7.val(hl7.parse(l_first), 'MSH', 10));
    ut.expect(ack_code(l_second)).to_equal('AA');
  end duplicate;

  procedure not_hl7 is
    l_before pls_integer;
    l_after  pls_integer;
    l_ack    varchar2(4000);
  begin
    select count(*) into l_before from hl7_messages;
    l_ack := inbound.receive('hello');
    select count(*) into l_after from hl7_messages;
    ut.expect(ack_code(l_ack)).to_equal('AR');
    ut.expect(hl7.val(hl7.parse(l_ack), 'MSH', 10)).to_equal('WR0');
    ut.expect(l_after).to_equal(l_before);
  end not_hl7;

  procedure no_control_id is
    l_ack varchar2(4000) := inbound.receive(
      'MSH|^~\&|REG|HOSP|WARDROUND|HOSP|20260302080000||ADT^A04^ADT_A01||P|2.5.1');
  begin
    ut.expect(ack_code(l_ack)).to_equal('AR');
    ut.expect(hl7.val(hl7.parse(l_ack), 'MSA', 3)).to_equal('MSH-3 and MSH-10 are needed');
  end no_control_id;

  procedure ignored_type is
  begin
    test_fixture.send('MSH|^~\&|REG|HOSP|WARDROUND|HOSP|20260302080000||SIU^S12^SIU_S12|S1|P|2.5.1');
    ut.expect(test_fixture.status_of('S1')).to_equal('IGNORED');
  end ignored_type;

  procedure error_then_next is
    l_ack varchar2(4000);
    l_n   pls_integer;
  begin
    l_ack := inbound.receive(test_fixture.adt('A04', 'F1', hm('08:00'), '9Z', p_control => 'B1'));
    l_ack := inbound.receive(test_fixture.adt('A04', 'F2', hm('08:05'), p_control => 'B2'));
    l_n := inbound.process;
    ut.expect(l_n).to_equal(1);
    ut.expect(test_fixture.status_of('B1')).to_equal('ERROR');
    ut.expect(test_fixture.status_of('B2')).to_equal('DONE');
  end error_then_next;

  procedure reprocess_after_mapping is
    l_id   hl7_messages.msg_id%type;
    l_n    pls_integer;
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', hm('08:00'), 'EDX', p_control => 'M1'));
    ut.expect(test_fixture.status_of('M1')).to_equal('ERROR');

    insert into code_value_aliases (code_set, source, alias, code_value)
    values (220, 'REG', 'EDX', codes.cd(220, 'ED'));
    select msg_id into l_id from hl7_messages where control_id = 'M1';
    inbound.reprocess(l_id);
    l_n := inbound.process;
    ut.expect(test_fixture.status_of('M1')).to_equal('DONE');
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-');
  end reprocess_after_mapping;

  procedure reprocess_done is
    l_id hl7_messages.msg_id%type;
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'D1'));
    select msg_id into l_id from hl7_messages where control_id = 'D1';
    inbound.reprocess(l_id);
  end reprocess_done;

  procedure purge_keeps_errors is
    l_n pls_integer;
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'G1'));
    test_fixture.send(test_fixture.adt('A04', 'F2', hm('08:00'), '9Z', p_control => 'G2'));
    ut.expect(inbound.purge_applied(sysdate - 1)).to_equal(0);
    l_n := inbound.purge_applied(sysdate + 1);
    ut.expect(count_of('G1')).to_equal(0);
    ut.expect(count_of('G2')).to_equal(1);
    ut.expect(test_fixture.visit('F1').status).to_equal('ACTIVE');
  end purge_keeps_errors;

  procedure process_max is
    l_ack varchar2(4000);
    l_n   pls_integer;
  begin
    l_ack := inbound.receive(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'Q1'));
    l_ack := inbound.receive(test_fixture.adt('A04', 'F2', hm('08:01'), p_control => 'Q2'));
    l_ack := inbound.receive(test_fixture.adt('A04', 'F3', hm('08:02'), p_control => 'Q3'));
    l_n := inbound.process(2);
    ut.expect(l_n).to_equal(2);
    ut.expect(test_fixture.status_of('Q3')).to_equal('NEW');
  end process_max;

  procedure bad_time_still_stored is
    l_ack varchar2(4000);
    l_at  date;
  begin
    l_ack := inbound.receive(replace(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'BT1'),
                                     '|20260302080000||ADT', '|2026-03-02||ADT'));
    select event_dt into l_at from hl7_messages where control_id = 'BT1';
    ut.expect(ack_code(l_ack)).to_equal('AA');
    ut.expect(l_at).to_be_null();
  end bad_time_still_stored;

  procedure lf_segments is
  begin
    test_fixture.send(replace(test_fixture.adt('A04', 'F1', hm('08:00'), p_control => 'LF1'), chr(13), chr(10)));
    ut.expect(test_fixture.status_of('LF1')).to_equal('DONE');
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-');
  end lf_segments;
end test_inbound;
/
