create or replace package body adt as

  c_types  constant number := 71;
  c_disp   constant number := 19;
  c_units  constant number := 220;

  type t_location is record (
    unit_cd  number,
    room     varchar2(10),
    bed      varchar2(10)
  );

  function event_time(p_msg hl7.t_message) return date is
  begin
    return coalesce(hl7.ts(hl7.val(p_msg, 'EVN', 6)),
                    hl7.ts(hl7.val(p_msg, 'EVN', 2)),
                    hl7.ts(hl7.val(p_msg, 'MSH', 7)));
  end event_time;

  -- The sending application, which is the source its codes are mapped
  -- from.
  function source(p_msg hl7.t_message) return varchar2 is
  begin
    return hl7.val(p_msg, 'MSH', 3);
  end source;

  -- The patient's MRN: the PID-3 identifier whose type (component 5) is
  -- MR, or the first one if none says.
  function mrn(p_msg hl7.t_message) return varchar2 is
    l_pid pls_integer := hl7.find(p_msg, 'PID');
  begin
    for i in 1 .. hl7.repetitions(p_msg, l_pid, 3) loop
      if hl7.get(p_msg, l_pid, 3, 5, i) = 'MR' then
        return hl7.get(p_msg, l_pid, 3, 1, i);
      end if;
    end loop;
    return hl7.get(p_msg, l_pid, 3);
  end mrn;

  -- Adds the patient, or updates them with whatever the message has.
  function upsert_person(p_msg hl7.t_message) return persons.person_id%type is
    l_pid     pls_integer := hl7.find(p_msg, 'PID');
    l_mrn     varchar2(4000) := mrn(p_msg);
    l_family  varchar2(60) := substr(hl7.get(p_msg, l_pid, 5, 1), 1, 60);
    l_given   varchar2(60) := substr(hl7.get(p_msg, l_pid, 5, 2), 1, 60);
    l_birth   date := hl7.ts(hl7.get(p_msg, l_pid, 7));
    l_sex     varchar2(4000) := hl7.get(p_msg, l_pid, 8);
    l_id      persons.person_id%type;
  begin
    if l_mrn is null then
      raise_application_error(wr_errors.bad_field, 'no medical record number in PID-3');
    elsif length(l_mrn) > 20 then
      raise_application_error(wr_errors.bad_field, 'medical record number "' || substr(l_mrn, 1, 40) || '" is too long');
    end if;
    -- HL7 has other values for sex (O, A, N); they're kept as unknown.
    if l_sex not in ('F', 'M') then
      l_sex := 'U';
    end if;

    merge into persons p
    using (select l_mrn as mrn from dual) s
       on (p.mrn = s.mrn)
     when matched then update
          set p.family_name = nvl(l_family, p.family_name),
              p.given_name = nvl(l_given, p.given_name),
              p.birth_date = nvl(l_birth, p.birth_date),
              p.sex = nvl(l_sex, p.sex),
              p.updated_at = sysdate
     when not matched then insert (mrn, family_name, given_name, birth_date, sex)
          values (l_mrn, nvl(l_family, 'UNKNOWN'), l_given, l_birth, l_sex);

    select person_id into l_id from persons where mrn = l_mrn;
    return l_id;
  end upsert_person;

  function fin(p_msg hl7.t_message) return varchar2 is
    l_fin varchar2(4000) := hl7.val(p_msg, 'PV1', 19);
  begin
    if l_fin is null then
      raise_application_error(wr_errors.bad_field, 'no visit number in PV1-19');
    elsif length(l_fin) > 20 then
      raise_application_error(wr_errors.bad_field, 'visit number "' || substr(l_fin, 1, 40) || '" is too long');
    end if;
    return l_fin;
  end fin;

  -- The visit the message is about, locked, or null if it isn't
  -- registered.
  function visit(p_fin varchar2) return encounters%rowtype is
    l_enc encounters%rowtype;
  begin
    select * into l_enc from encounters where fin = p_fin for update;
    return l_enc;
  exception
    when no_data_found then
      return null;
  end visit;

  -- The same, raising waiting_for if the visit isn't registered yet.
  function registered_visit(p_msg hl7.t_message) return encounters%rowtype is
    l_fin varchar2(20) := fin(p_msg);
    l_enc encounters%rowtype := visit(l_fin);
  begin
    if l_enc.encntr_id is null then
      raise_application_error(wr_errors.waiting_for, 'visit ' || l_fin || ' isn''t registered yet');
    end if;
    return l_enc;
  end registered_visit;

  function location(p_msg hl7.t_message) return t_location is
    l_loc t_location;
  begin
    if hl7.val(p_msg, 'PV1', 3, 1) is null then
      raise_application_error(wr_errors.bad_field, 'no unit in PV1-3');
    end if;
    l_loc.unit_cd := codes.lookup(c_units, source(p_msg), hl7.val(p_msg, 'PV1', 3, 1));
    l_loc.room := substr(hl7.val(p_msg, 'PV1', 3, 2), 1, 10);
    l_loc.bed := substr(hl7.val(p_msg, 'PV1', 3, 3), 1, 10);
    return l_loc;
  end location;

  -- Puts the patient in p_loc from p_at. The stretch of location history
  -- p_at falls in is split there; the new stretch runs to where the old
  -- one ended, so a later move already applied stays in place.
  procedure move(p_enc encounters%rowtype, p_at date, p_loc t_location) is
    l_cur    encounter_locations%rowtype;
    l_first  date;
  begin
    if p_at < p_enc.arrive_dt then
      raise_application_error(wr_errors.out_of_step,
        'move at ' || to_char(p_at, 'YYYY-MM-DD HH24:MI') || ' is before arrival');
    elsif p_at >= p_enc.disch_dt then
      raise_application_error(wr_errors.out_of_step,
        'move at ' || to_char(p_at, 'YYYY-MM-DD HH24:MI') || ' is after discharge');
    end if;

    begin
      select * into l_cur
        from encounter_locations
       where encntr_id = p_enc.encntr_id
         and beg_dt <= p_at
         and (end_dt is null or end_dt > p_at);
    exception
      when no_data_found then
        -- Before the first stretch, or there's no history yet.
        select min(beg_dt) into l_first from encounter_locations where encntr_id = p_enc.encntr_id;
        insert into encounter_locations (encntr_id, beg_dt, end_dt, unit_cd, room, bed)
        values (p_enc.encntr_id, p_at, l_first, p_loc.unit_cd, p_loc.room, p_loc.bed);
        return;
    end;

    if l_cur.unit_cd = p_loc.unit_cd
       and decode(l_cur.room, p_loc.room, 1, 0) = 1
       and decode(l_cur.bed, p_loc.bed, 1, 0) = 1 then
      return; -- already there: a resend
    elsif l_cur.beg_dt = p_at then
      -- The move that started this stretch, corrected.
      update encounter_locations
         set unit_cd = p_loc.unit_cd, room = p_loc.room, bed = p_loc.bed
       where encntr_id = p_enc.encntr_id and beg_dt = l_cur.beg_dt;
    else
      update encounter_locations
         set end_dt = p_at
       where encntr_id = p_enc.encntr_id and beg_dt = l_cur.beg_dt;
      insert into encounter_locations (encntr_id, beg_dt, end_dt, unit_cd, room, bed)
      values (p_enc.encntr_id, p_at, l_cur.end_dt, p_loc.unit_cd, p_loc.room, p_loc.bed);
    end if;
  end move;

  -- Replaces the visit's diagnoses with the message's DG1 segments, if
  -- it has any. DG1-15 = 1 marks the principal diagnosis; if no segment
  -- sets DG1-15, the first is taken as principal.
  procedure diagnoses(p_msg hl7.t_message, p_encntr_id number) is
    l_seg     pls_integer;
    l_ranked  boolean := false;
    l_n       pls_integer := 0;
  begin
    if hl7.find(p_msg, 'DG1') is null then
      return;
    end if;
    loop
      l_seg := hl7.find(p_msg, 'DG1', l_n + 1);
      exit when l_seg is null;
      l_n := l_n + 1;
      l_ranked := l_ranked or hl7.get(p_msg, l_seg, 15) is not null;
    end loop;

    delete from diagnoses where encntr_id = p_encntr_id;
    for i in 1 .. l_n loop
      l_seg := hl7.find(p_msg, 'DG1', i);
      if hl7.get(p_msg, l_seg, 3) is null then
        raise_application_error(wr_errors.bad_field, 'no diagnosis code in DG1-3 of DG1 number ' || i);
      end if;
      insert into diagnoses (encntr_id, seq, icd10, description, kind)
      values (p_encntr_id, i,
              substr(hl7.get(p_msg, l_seg, 3, 1), 1, 8),
              substr(hl7.get(p_msg, l_seg, 3, 2), 1, 200),
              case
                when l_ranked and hl7.get(p_msg, l_seg, 15) = '1' then 'PRINCIPAL'
                when not l_ranked and i = 1 then 'PRINCIPAL'
                else 'SECONDARY'
              end);
    end loop;
  end diagnoses;

  -- A04, and A01 for a visit that wasn't registered first.
  procedure register(p_msg hl7.t_message, p_inpatient boolean) is
    l_fin     varchar2(20) := fin(p_msg);
    l_enc     encounters%rowtype := visit(l_fin);
    l_person  persons.person_id%type := upsert_person(p_msg);
    l_at      date;
    l_type    number;
  begin
    if l_enc.encntr_id is not null then
      return; -- already registered: a resend
    end if;
    l_at := coalesce(hl7.ts(hl7.val(p_msg, 'PV1', 44)), event_time(p_msg));
    l_type := case
                when p_inpatient then codes.cd(c_types, 'INPATIENT')
                else codes.lookup(c_types, source(p_msg), hl7.val(p_msg, 'PV1', 2))
              end;
    if l_type is null then
      raise_application_error(wr_errors.bad_field, 'no patient class in PV1-2');
    end if;

    insert into encounters (person_id, fin, encntr_type_cd, arrive_dt, inpatient_dt)
    values (l_person, l_fin, l_type, l_at,
            case when l_type = codes.cd(c_types, 'INPATIENT') then l_at end)
    returning encntr_id, person_id, fin, encntr_type_cd, status, arrive_dt, inpatient_dt,
              disch_dt, disch_disp_cd, updated_at
         into l_enc;
    move(l_enc, l_at, location(p_msg));
    diagnoses(p_msg, l_enc.encntr_id);
  end register;

  procedure admit(p_msg hl7.t_message) is
    l_enc  encounters%rowtype := visit(fin(p_msg));
    l_at   date := event_time(p_msg);
    l_id   persons.person_id%type;
  begin
    if l_enc.encntr_id is null then
      register(p_msg, true);
      return;
    elsif l_enc.status <> 'ACTIVE' then
      raise_application_error(wr_errors.out_of_step, 'visit ' || l_enc.fin || ' is ' || lower(l_enc.status));
    end if;
    l_id := upsert_person(p_msg);
    update encounters
       set encntr_type_cd = codes.cd(c_types, 'INPATIENT'),
           inpatient_dt = nvl(inpatient_dt, greatest(l_at, arrive_dt)),
           updated_at = sysdate
     where encntr_id = l_enc.encntr_id;
    move(l_enc, greatest(l_at, l_enc.arrive_dt), location(p_msg));
    diagnoses(p_msg, l_enc.encntr_id);
  end admit;

  procedure transfer(p_msg hl7.t_message) is
    l_enc encounters%rowtype := registered_visit(p_msg);
  begin
    if l_enc.status = 'CANCELLED' then
      raise_application_error(wr_errors.out_of_step, 'visit ' || l_enc.fin || ' is cancelled');
    end if;
    move(l_enc, event_time(p_msg), location(p_msg));
  end transfer;

  procedure discharge(p_msg hl7.t_message) is
    l_enc    encounters%rowtype := registered_visit(p_msg);
    l_at     date := coalesce(hl7.ts(hl7.val(p_msg, 'PV1', 45)), event_time(p_msg));
    l_later  pls_integer;
  begin
    if l_enc.status = 'CANCELLED' then
      raise_application_error(wr_errors.out_of_step, 'visit ' || l_enc.fin || ' is cancelled');
    elsif l_at < l_enc.arrive_dt then
      raise_application_error(wr_errors.out_of_step, 'discharge is before arrival');
    end if;
    select count(*) into l_later
      from encounter_locations
     where encntr_id = l_enc.encntr_id and beg_dt >= l_at;
    if l_later > 0 then
      raise_application_error(wr_errors.out_of_step,
        'discharge at ' || to_char(l_at, 'YYYY-MM-DD HH24:MI') || ' is before the last move');
    end if;

    update encounters
       set status = 'DISCHARGED',
           disch_dt = l_at,
           disch_disp_cd = codes.lookup(c_disp, source(p_msg), hl7.val(p_msg, 'PV1', 36)),
           updated_at = sysdate
     where encntr_id = l_enc.encntr_id;
    update encounter_locations
       set end_dt = l_at
     where encntr_id = l_enc.encntr_id
       and beg_dt = (select max(beg_dt) from encounter_locations where encntr_id = l_enc.encntr_id);
    diagnoses(p_msg, l_enc.encntr_id);
  end discharge;

  procedure update_patient(p_msg hl7.t_message) is
    l_id   persons.person_id%type := upsert_person(p_msg);
    l_enc  encounters%rowtype;
  begin
    if hl7.val(p_msg, 'PV1', 19) is not null then
      l_enc := visit(fin(p_msg));
      if l_enc.encntr_id is not null then
        diagnoses(p_msg, l_enc.encntr_id);
      end if;
    end if;
  end update_patient;

  -- An admission of a patient who was already here, from the emergency
  -- department, makes the visit an emergency visit again; a direct
  -- admission is cancelled altogether.
  procedure cancel_admit(p_msg hl7.t_message) is
    l_enc encounters%rowtype := registered_visit(p_msg);
  begin
    if l_enc.inpatient_dt > l_enc.arrive_dt then
      update encounters
         set encntr_type_cd = codes.cd(c_types, 'EMERGENCY'), inpatient_dt = null, updated_at = sysdate
       where encntr_id = l_enc.encntr_id;
    else
      update encounters
         set status = 'CANCELLED', updated_at = sysdate
       where encntr_id = l_enc.encntr_id;
    end if;
  end cancel_admit;

  procedure cancel_discharge(p_msg hl7.t_message) is
    l_enc encounters%rowtype := registered_visit(p_msg);
  begin
    if l_enc.status = 'ACTIVE' then
      return; -- already cancelled: a resend
    elsif l_enc.status <> 'DISCHARGED' then
      raise_application_error(wr_errors.out_of_step, 'visit ' || l_enc.fin || ' is ' || lower(l_enc.status));
    end if;
    update encounters
       set status = 'ACTIVE', disch_dt = null, disch_disp_cd = null, updated_at = sysdate
     where encntr_id = l_enc.encntr_id;
    update encounter_locations
       set end_dt = null
     where encntr_id = l_enc.encntr_id
       and beg_dt = (select max(beg_dt) from encounter_locations where encntr_id = l_enc.encntr_id);
  end cancel_discharge;

  procedure apply_message(p_msg hl7.t_message) is
  begin
    case hl7.val(p_msg, 'MSH', 9, 2)
      when 'A04' then register(p_msg, false);
      when 'A01' then admit(p_msg);
      when 'A06' then admit(p_msg);
      when 'A02' then transfer(p_msg);
      when 'A03' then discharge(p_msg);
      when 'A08' then update_patient(p_msg);
      when 'A11' then cancel_admit(p_msg);
      when 'A13' then cancel_discharge(p_msg);
    end case;
  end apply_message;

  function handles(p_event varchar2) return boolean is
  begin
    return p_event in ('A01', 'A02', 'A03', 'A04', 'A06', 'A08', 'A11', 'A13');
  end handles;
end adt;
/
