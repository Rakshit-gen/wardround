create or replace package body test_fixture as

  g_next pls_integer := 0;

  function control(p_control varchar2) return varchar2 is
  begin
    if p_control is not null then
      return p_control;
    end if;
    g_next := g_next + 1;
    return 'T' || g_next;
  end control;

  function hl7_time(p_at date) return varchar2 is
  begin
    return to_char(p_at, 'YYYYMMDDHH24MISS');
  end hl7_time;

  function seg(p_id varchar2, p_fields t_fields) return varchar2 is
    l_out varchar2(32767) := p_id;
    l_last pls_integer := nvl(p_fields.last, 0);
  begin
    for i in 1 .. l_last loop
      l_out := l_out || '|' || case when p_fields.exists(i) then p_fields(i) end;
    end loop;
    return l_out;
  end seg;

  function msh(p_sender varchar2, p_type varchar2, p_at date, p_control varchar2) return varchar2 is
  begin
    return 'MSH|^~\&|' || p_sender || '|HOSP|WARDROUND|HOSP|' || hl7_time(p_at) || '||' || p_type
        || '|' || control(p_control) || '|P|2.5.1';
  end msh;

  function adt(
    p_event    varchar2,
    p_fin      varchar2,
    p_at       date,
    p_unit     varchar2 default 'ED',
    p_room     varchar2 default null,
    p_bed      varchar2 default null,
    p_class    varchar2 default 'E',
    p_mrn      varchar2 default 'M1',
    p_disp     varchar2 default null,
    p_extra    varchar2 default null,
    p_control  varchar2 default null,
    p_arrived  date default null,
    p_occurred date default null
  ) return varchar2 is
    l_evn t_fields;
    l_pid t_fields;
    l_pv1 t_fields;
  begin
    l_evn(1) := p_event;
    l_evn(2) := hl7_time(p_at);
    l_evn(6) := case when p_occurred is not null then hl7_time(p_occurred) end;
    l_pid(1) := '1';
    l_pid(3) := p_mrn || '^^^HOSP^MR';
    l_pid(5) := 'DOE^JANE';
    l_pid(7) := '19800101';
    l_pid(8) := 'F';
    l_pv1(1) := '1';
    l_pv1(2) := p_class;
    l_pv1(3) := p_unit || '^' || p_room || '^' || p_bed;
    l_pv1(19) := p_fin;
    l_pv1(36) := p_disp;
    l_pv1(44) := case when p_arrived is not null then hl7_time(p_arrived) end;
    return msh('REG', 'ADT^' || p_event || '^ADT_A01', p_at, p_control) || chr(13)
        || seg('EVN', l_evn) || chr(13)
        || seg('PID', l_pid) || chr(13)
        || seg('PV1', l_pv1)
        || case when p_extra is not null then chr(13) || p_extra end;
  end adt;

  function orm(
    p_placer        varchar2,
    p_fin           varchar2,
    p_test          varchar2,
    p_at            date,
    p_stat          boolean default false,
    p_control_code  varchar2 default 'NW',
    p_control       varchar2 default null
  ) return varchar2 is
    l_pid t_fields;
    l_pv1 t_fields;
    l_orc t_fields;
    l_obr t_fields;
  begin
    l_pid(1) := '1';
    l_pid(3) := 'M1^^^HOSP^MR';
    l_pv1(1) := '1';
    l_pv1(19) := p_fin;
    l_orc(1) := p_control_code;
    l_orc(2) := p_placer;
    l_orc(9) := hl7_time(p_at);
    l_obr(1) := '1';
    l_obr(2) := p_placer;
    l_obr(4) := p_test;
    l_obr(27) := '^^^^^' || case when p_stat then 'S' else 'R' end;
    return msh('CPOE', 'ORM^O01^ORM_O01', p_at, p_control) || chr(13)
        || seg('PID', l_pid) || chr(13)
        || seg('PV1', l_pv1) || chr(13)
        || seg('ORC', l_orc) || chr(13)
        || seg('OBR', l_obr);
  end orm;

  function obx(
    p_n       pls_integer,
    p_loinc   varchar2,
    p_value   varchar2,
    p_units   varchar2 default null,
    p_range   varchar2 default null,
    p_flag    varchar2 default null,
    p_status  varchar2 default 'F'
  ) return varchar2 is
    l_obx t_fields;
  begin
    l_obx(1) := p_n;
    l_obx(2) := 'NM';
    l_obx(3) := p_loinc || '^^LN';
    l_obx(5) := p_value;
    l_obx(6) := p_units;
    l_obx(7) := p_range;
    l_obx(8) := p_flag;
    l_obx(11) := p_status;
    return seg('OBX', l_obx);
  end obx;

  function oru(
    p_placer     varchar2,
    p_fin        varchar2,
    p_collected  date,
    p_reported   date,
    p_obx        varchar2,
    p_control    varchar2 default null
  ) return varchar2 is
    l_pid t_fields;
    l_pv1 t_fields;
    l_obr t_fields;
  begin
    l_pid(1) := '1';
    l_pid(3) := 'M1^^^HOSP^MR';
    l_pv1(1) := '1';
    l_pv1(19) := p_fin;
    l_obr(1) := '1';
    l_obr(2) := p_placer;
    l_obr(7) := hl7_time(p_collected);
    l_obr(22) := hl7_time(p_reported);
    return msh('LAB', 'ORU^R01^ORU_R01', p_reported, p_control) || chr(13)
        || seg('PID', l_pid) || chr(13)
        || seg('PV1', l_pv1) || chr(13)
        || seg('OBR', l_obr) || chr(13)
        || p_obx;
  end oru;

  procedure send(p_raw varchar2) is
    l_ack  varchar2(4000) := inbound.receive(p_raw);
    l_n    pls_integer := inbound.process;
  begin
    null;
  end send;

  function status_of(p_control varchar2) return varchar2 is
    l_status hl7_messages.status%type;
  begin
    select status into l_status from hl7_messages where control_id = p_control;
    return l_status;
  end status_of;

  function error_of(p_control varchar2) return varchar2 is
    l_error hl7_messages.error%type;
  begin
    select error into l_error from hl7_messages where control_id = p_control;
    return l_error;
  end error_of;

  function visit(p_fin varchar2) return encounters%rowtype is
    l_enc encounters%rowtype;
  begin
    select * into l_enc from encounters where fin = p_fin;
    return l_enc;
  end visit;

  function locations(p_fin varchar2) return varchar2 is
    l_out varchar2(4000);
  begin
    select listagg(cv.meaning || ' ' || to_char(l.beg_dt, 'HH24:MI') || '-' || to_char(l.end_dt, 'HH24:MI'), ', ')
             within group (order by l.beg_dt)
      into l_out
      from encounter_locations l
      join encounters e on e.encntr_id = l.encntr_id
      join code_values cv on cv.code_value = l.unit_cd
     where e.fin = p_fin;
    return l_out;
  end locations;
end test_fixture;
/
