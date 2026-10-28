create or replace package body test_lab as

  function at(p_hhmi varchar2) return date is
  begin
    return to_date('2026-03-02 ' || p_hhmi, 'YYYY-MM-DD HH24:MI');
  end at;

  function order_of(p_placer varchar2) return orders%rowtype is
    l_order orders%rowtype;
  begin
    select * into l_order from orders where placer_no = p_placer;
    return l_order;
  end order_of;

  -- The current version of result p_meaning for order p_placer.
  function result_of(p_placer varchar2, p_meaning varchar2) return clinical_events%rowtype is
    l_ce clinical_events%rowtype;
  begin
    select ce.* into l_ce
      from clinical_events ce
      join orders o on o.order_id = ce.order_id
     where o.placer_no = p_placer and ce.event_cd = codes.cd(72, p_meaning) and ce.valid_until is null;
    return l_ce;
  end result_of;

  function versions(p_placer varchar2) return pls_integer is
    l_n pls_integer;
  begin
    select count(*) into l_n
      from clinical_events ce join orders o on o.order_id = ce.order_id
     where o.placer_no = p_placer;
    return l_n;
  end versions;

  function cbc(p_status varchar2 default 'F', p_wbc varchar2 default '7.2') return varchar2 is
  begin
    return test_fixture.obx(1, '6690-2', p_wbc, '10*3/uL', '4.0-11.0', 'N', p_status) || chr(13)
        || test_fixture.obx(2, '718-7', '9.8', 'g/dL', '12.0-16.0', 'L', p_status);
  end cbc;

  procedure visit is
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', at('08:00')));
  end visit;

  procedure new_order is
    l_order orders%rowtype;
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    l_order := order_of('P1');
    ut.expect(codes.meaning(l_order.catalog_cd)).to_equal('CBC');
    ut.expect(l_order.priority).to_equal('ROUTINE');
    ut.expect(l_order.status).to_equal('ORDERED');
    ut.expect(l_order.ordered_dt).to_equal(at('08:15'));
    ut.expect(l_order.encntr_id).to_equal(test_fixture.visit('F1').encntr_id);
  end new_order;

  procedure stat_order is
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'TROP', at('08:15'), p_stat => true));
    ut.expect(order_of('P1').priority).to_equal('STAT');
  end stat_order;

  procedure order_resent is
    l_n pls_integer;
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    select count(*) into l_n from orders where placer_no = 'P1';
    ut.expect(l_n).to_equal(1);
  end order_resent;

  procedure order_before_visit is
  begin
    test_fixture.send(test_fixture.orm('P2', 'F9', 'CBC', at('08:15'), p_control => 'O1'));
    ut.expect(test_fixture.status_of('O1')).to_equal('HELD');
    test_fixture.send(test_fixture.adt('A04', 'F9', at('08:10')));
    ut.expect(test_fixture.status_of('O1')).to_equal('DONE');
    ut.expect(order_of('P2').status).to_equal('ORDERED');
  end order_before_visit;

  procedure final_results is
    l_order  orders%rowtype;
    l_wbc    clinical_events%rowtype;
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc));
    l_order := order_of('P1');
    l_wbc := result_of('P1', 'WBC');
    ut.expect(l_order.status).to_equal('COMPLETED');
    ut.expect(l_order.collected_dt).to_equal(at('08:30'));
    ut.expect(l_order.verified_dt).to_equal(at('09:05'));
    ut.expect(l_wbc.result_num).to_equal(7.2);
    ut.expect(l_wbc.units).to_equal('10*3/uL');
    ut.expect(l_wbc.normal_range).to_equal('4.0-11.0');
    ut.expect(l_wbc.observed_dt).to_equal(at('08:30'));
    ut.expect(result_of('P1', 'HGB').abnormal).to_equal('L');
  end final_results;

  procedure preliminary_then_final is
    l_prelim clinical_events%rowtype;
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('08:50'), cbc('P', '6.9')));
    ut.expect(order_of('P1').status).to_equal('ORDERED');
    ut.expect(order_of('P1').verified_dt).to_be_null();

    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc('F', '7.2')));
    select ce.* into l_prelim
      from clinical_events ce join orders o on o.order_id = ce.order_id
     where o.placer_no = 'P1' and ce.event_cd = codes.cd(72, 'WBC') and ce.status = 'P';
    ut.expect(l_prelim.valid_until).to_equal(at('09:05'));
    ut.expect(result_of('P1', 'WBC').result_val).to_equal('7.2');
    ut.expect(order_of('P1').verified_dt).to_equal(at('09:05'));
  end preliminary_then_final;

  procedure correction is
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('11:40'), cbc('C', '72')));
    ut.expect(result_of('P1', 'WBC').status).to_equal('C');
    ut.expect(result_of('P1', 'WBC').result_num).to_equal(72);
    ut.expect(versions('P1')).to_equal(4); -- WBC and HGB, each final then corrected
    ut.expect(order_of('P1').verified_dt).to_equal(at('09:05'));
  end correction;

  procedure late_preliminary is
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('08:50'), cbc('P', '6.9'), p_control => 'L1'));
    ut.expect(test_fixture.status_of('L1')).to_equal('DONE');
    ut.expect(versions('P1')).to_equal(2);
    ut.expect(result_of('P1', 'WBC').status).to_equal('F');
  end late_preliminary;

  procedure results_before_order is
  begin
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc, p_control => 'E1'));
    ut.expect(test_fixture.status_of('E1')).to_equal('HELD');
    ut.expect(test_fixture.error_of('E1')).to_equal('order P1 hasn''t arrived yet');
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    ut.expect(test_fixture.status_of('E1')).to_equal('DONE');
    ut.expect(order_of('P1').status).to_equal('COMPLETED');
  end results_before_order;

  procedure cancelled_order is
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:20'), p_control_code => 'CA'));
    ut.expect(order_of('P1').status).to_equal('CANCELLED');
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc, p_control => 'E2'));
    ut.expect(test_fixture.status_of('E2')).to_equal('ERROR');
    ut.expect(test_fixture.error_of('E2')).to_equal('order P1 was cancelled');
    ut.expect(versions('P1')).to_equal(0);
  end cancelled_order;

  procedure cancel_after_results is
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'), cbc));
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('09:10'), p_control_code => 'CA', p_control => 'C1'));
    ut.expect(test_fixture.status_of('C1')).to_equal('ERROR');
    ut.expect(order_of('P1').status).to_equal('COMPLETED');
  end cancel_after_results;

  procedure text_values is
    l_ce clinical_events%rowtype;
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'TROP', at('08:15'), p_stat => true));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:20'), at('09:00'),
                      test_fixture.obx(1, '10839-9', '<0.01', 'ng/mL', '<0.04', 'W')));
    l_ce := result_of('P1', 'TROPI');
    ut.expect(l_ce.result_val).to_equal('<0.01');
    ut.expect(l_ce.result_num).to_be_null();
    ut.expect(l_ce.abnormal).to_equal('A');
  end text_values;

  procedure unmapped_result is
  begin
    test_fixture.send(test_fixture.orm('P1', 'F1', 'CBC', at('08:15')));
    test_fixture.send(test_fixture.oru('P1', 'F1', at('08:30'), at('09:05'),
                      cbc || chr(13) || test_fixture.obx(3, '9999-9', '1'), p_control => 'E3'));
    ut.expect(test_fixture.status_of('E3')).to_equal('ERROR');
    ut.expect(test_fixture.error_of('E3')).to_equal('LAB code "9999-9" isn''t mapped in code set 72');
    ut.expect(versions('P1')).to_equal(0);
    ut.expect(order_of('P1').status).to_equal('ORDERED');
  end unmapped_result;
end test_lab;
/
