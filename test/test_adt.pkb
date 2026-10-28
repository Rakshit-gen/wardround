create or replace package body test_adt as

  function at(p_hhmi varchar2) return date is
  begin
    return to_date('2026-03-02 ' || p_hhmi, 'YYYY-MM-DD HH24:MI');
  end at;

  function type_of(p_fin varchar2) return varchar2 is
  begin
    return codes.meaning(test_fixture.visit(p_fin).encntr_type_cd);
  end type_of;

  function dg1(p_n pls_integer, p_code varchar2, p_text varchar2, p_rank varchar2 default null) return varchar2 is
    l_f test_fixture.t_fields;
  begin
    l_f(1) := p_n;
    l_f(3) := p_code || '^' || p_text || '^I10';
    l_f(15) := p_rank;
    return test_fixture.seg('DG1', l_f);
  end dg1;

  -- An emergency visit F1 from 08:00, admitted to 4W at 10:00.
  procedure ed_then_ward is
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', at('08:00')));
    test_fixture.send(test_fixture.adt('A01', 'F1', at('10:00'), '4W', '401', 'A'));
  end ed_then_ward;

  procedure register_emergency is
    l_enc encounters%rowtype;
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', at('08:00'), 'ED', 'BAY', '3', p_control => 'R1'));
    l_enc := test_fixture.visit('F1');
    ut.expect(test_fixture.status_of('R1')).to_equal('DONE');
    ut.expect(l_enc.status).to_equal('ACTIVE');
    ut.expect(type_of('F1')).to_equal('EMERGENCY');
    ut.expect(l_enc.arrive_dt).to_equal(at('08:00'));
    ut.expect(l_enc.inpatient_dt).to_be_null();
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-');
  end register_emergency;

  procedure admit_from_ed is
    l_enc encounters%rowtype;
  begin
    ed_then_ward;
    l_enc := test_fixture.visit('F1');
    ut.expect(type_of('F1')).to_equal('INPATIENT');
    ut.expect(l_enc.arrive_dt).to_equal(at('08:00'));
    ut.expect(l_enc.inpatient_dt).to_equal(at('10:00'));
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-10:00, 4W 10:00-');
  end admit_from_ed;

  procedure direct_admit is
    l_enc encounters%rowtype;
  begin
    test_fixture.send(test_fixture.adt('A01', 'F2', at('09:30'), '5E', p_class => 'I'));
    l_enc := test_fixture.visit('F2');
    ut.expect(type_of('F2')).to_equal('INPATIENT');
    ut.expect(l_enc.inpatient_dt).to_equal(l_enc.arrive_dt);
    ut.expect(test_fixture.locations('F2')).to_equal('5E 09:30-');
  end direct_admit;

  procedure mrn_by_type is
    l_mrn persons.mrn%type;
  begin
    test_fixture.send(replace(test_fixture.adt('A04', 'F1', at('08:00')),
                              'M1^^^HOSP^MR', 'X9^^^OTHER^PI~M5^^^HOSP^MR'));
    select p.mrn into l_mrn
      from persons p join encounters e on e.person_id = p.person_id
     where e.fin = 'F1';
    ut.expect(l_mrn).to_equal('M5');
  end mrn_by_type;

  procedure transfers_out_of_order is
  begin
    ed_then_ward;
    test_fixture.send(test_fixture.adt('A02', 'F1', at('14:00'), 'ICU'));
    test_fixture.send(test_fixture.adt('A02', 'F1', at('12:00'), '5E'));
    ut.expect(test_fixture.locations('F1'))
      .to_equal('ED 08:00-10:00, 4W 10:00-12:00, 5E 12:00-14:00, ICU 14:00-');
  end transfers_out_of_order;

  procedure transfer_resent is
  begin
    ed_then_ward;
    test_fixture.send(test_fixture.adt('A02', 'F1', at('12:00'), 'ICU', p_control => 'X1'));
    test_fixture.send(test_fixture.adt('A02', 'F1', at('12:00'), 'ICU', p_control => 'X1'));
    test_fixture.send(test_fixture.adt('A02', 'F1', at('12:00'), 'ICU', p_control => 'X2'));
    ut.expect(test_fixture.status_of('X2')).to_equal('DONE');
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-10:00, 4W 10:00-12:00, ICU 12:00-');
  end transfer_resent;

  procedure held_until_registered is
  begin
    test_fixture.send(test_fixture.adt('A02', 'F3', at('09:00'), '4W', p_control => 'H1'));
    ut.expect(test_fixture.status_of('H1')).to_equal('HELD');
    ut.expect(test_fixture.error_of('H1')).to_equal('visit F3 isn''t registered yet');

    test_fixture.send(test_fixture.adt('A04', 'F3', at('08:00')));
    ut.expect(test_fixture.status_of('H1')).to_equal('DONE');
    ut.expect(test_fixture.error_of('H1')).to_be_null();
    ut.expect(test_fixture.locations('F3')).to_equal('ED 08:00-09:00, 4W 09:00-');
  end held_until_registered;

  procedure discharge is
    l_enc encounters%rowtype;
  begin
    ed_then_ward;
    test_fixture.send(test_fixture.adt('A03', 'F1', at('18:00'), '4W', p_disp => '01'));
    l_enc := test_fixture.visit('F1');
    ut.expect(l_enc.status).to_equal('DISCHARGED');
    ut.expect(l_enc.disch_dt).to_equal(at('18:00'));
    ut.expect(codes.meaning(l_enc.disch_disp_cd)).to_equal('HOME');
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-10:00, 4W 10:00-18:00');
  end discharge;

  procedure discharge_before_move is
  begin
    ed_then_ward;
    test_fixture.send(test_fixture.adt('A03', 'F1', at('09:00'), p_disp => '01', p_control => 'D1'));
    ut.expect(test_fixture.status_of('D1')).to_equal('ERROR');
    ut.expect(test_fixture.error_of('D1')).to_be_like('%is before the last move');
    ut.expect(test_fixture.visit('F1').status).to_equal('ACTIVE');
  end discharge_before_move;

  procedure cancel_discharge is
    l_enc encounters%rowtype;
  begin
    ed_then_ward;
    test_fixture.send(test_fixture.adt('A03', 'F1', at('18:00'), p_disp => '01'));
    test_fixture.send(test_fixture.adt('A13', 'F1', at('18:30')));
    l_enc := test_fixture.visit('F1');
    ut.expect(l_enc.status).to_equal('ACTIVE');
    ut.expect(l_enc.disch_dt).to_be_null();
    ut.expect(l_enc.disch_disp_cd).to_be_null();
    ut.expect(test_fixture.locations('F1')).to_equal('ED 08:00-10:00, 4W 10:00-');
  end cancel_discharge;

  procedure cancel_admit_from_ed is
    l_enc encounters%rowtype;
  begin
    ed_then_ward;
    test_fixture.send(test_fixture.adt('A11', 'F1', at('10:30')));
    l_enc := test_fixture.visit('F1');
    ut.expect(l_enc.status).to_equal('ACTIVE');
    ut.expect(type_of('F1')).to_equal('EMERGENCY');
    ut.expect(l_enc.inpatient_dt).to_be_null();
  end cancel_admit_from_ed;

  procedure cancel_direct_admit is
  begin
    test_fixture.send(test_fixture.adt('A01', 'F2', at('09:30'), '5E', p_class => 'I'));
    test_fixture.send(test_fixture.adt('A11', 'F2', at('09:45')));
    ut.expect(test_fixture.visit('F2').status).to_equal('CANCELLED');
  end cancel_direct_admit;

  procedure update_patient is
    l_person persons%rowtype;
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', at('08:00')));
    test_fixture.send(replace(replace(test_fixture.adt('A08', 'F1', at('08:20')),
                                      'DOE^JANE', 'ROE^JANET'), '|F' || chr(13) || 'PV1', '|M' || chr(13) || 'PV1'));
    select * into l_person from persons where mrn = 'M1';
    ut.expect(l_person.family_name).to_equal('ROE');
    ut.expect(l_person.given_name).to_equal('JANET');
    ut.expect(l_person.sex).to_equal('M');
    ut.expect(l_person.birth_date).to_equal(date '1980-01-01');
  end update_patient;

  procedure diagnoses is
    l_principal  diagnoses.icd10%type;
    l_count      pls_integer;
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', at('08:00'),
                      p_extra => dg1(1, 'R07.9', 'Chest pain')));
    test_fixture.send(test_fixture.adt('A08', 'F1', at('12:00'),
                      p_extra => dg1(1, 'E11.9', 'Type 2 diabetes', '2') || chr(13)
                                 || dg1(2, 'I21.4', 'NSTEMI', '1')));
    select count(*) into l_count from diagnoses d join encounters e on e.encntr_id = d.encntr_id where e.fin = 'F1';
    select d.icd10 into l_principal
      from diagnoses d join encounters e on e.encntr_id = d.encntr_id
     where e.fin = 'F1' and d.kind = 'PRINCIPAL';
    ut.expect(l_count).to_equal(2);
    ut.expect(l_principal).to_equal('I21.4');
  end diagnoses;

  procedure unmapped_unit is
  begin
    test_fixture.send(test_fixture.adt('A04', 'F1', at('08:00'), '9Z', p_control => 'U1'));
    ut.expect(test_fixture.status_of('U1')).to_equal('ERROR');
    ut.expect(test_fixture.error_of('U1')).to_equal('REG code "9Z" isn''t mapped in code set 220');
    ut.expect(test_fixture.locations('F1')).to_be_null();
  end unmapped_unit;
end test_adt;
/
