-- Reference data: the code sets, their values, what each feed calls
-- them, the hospital's units and the lab's turnaround targets.
--
-- Feeds: REG is registration (ADT), CPOE is order entry (ORM), LAB is
-- the lab system (ORU). Dispositions are the UB-04 patient status codes
-- registration sends in PV1-36; results are LOINC codes, as most lab
-- systems send in OBX-3.

declare
  procedure code_set(p_set number, p_name varchar2, p_description varchar2) is
  begin
    insert into code_sets (code_set, name, description) values (p_set, p_name, p_description);
  end code_set;

  -- Adds a value and returns its code.
  function add_value(p_set number, p_meaning varchar2, p_display varchar2) return number is
    l_cd number;
  begin
    insert into code_values (code_set, meaning, display)
    values (p_set, p_meaning, p_display)
    returning code_value into l_cd;
    return l_cd;
  end add_value;

  procedure add_alias(p_set number, p_source varchar2, p_alias varchar2, p_cd number) is
  begin
    insert into code_value_aliases (code_set, source, alias, code_value)
    values (p_set, p_source, p_alias, p_cd);
  end add_alias;

  procedure coded(p_set number, p_meaning varchar2, p_display varchar2, p_source varchar2, p_alias varchar2) is
  begin
    add_alias(p_set, p_source, p_alias, add_value(p_set, p_meaning, p_display));
  end coded;

  procedure unit(p_meaning varchar2, p_display varchar2, p_kind varchar2, p_beds number) is
    l_cd number := add_value(220, p_meaning, p_display);
  begin
    add_alias(220, 'REG', p_meaning, l_cd);
    insert into units (unit_cd, kind, staffed_beds) values (l_cd, p_kind, p_beds);
  end unit;

  procedure orderable(p_meaning varchar2, p_display varchar2, p_stat number, p_routine number) is
    l_cd number := add_value(200, p_meaning, p_display);
  begin
    add_alias(200, 'CPOE', p_meaning, l_cd);
    add_alias(200, 'LAB', p_meaning, l_cd);
    insert into tat_targets (catalog_cd, priority, minutes) values (l_cd, 'STAT', p_stat);
    if p_routine is not null then
      insert into tat_targets (catalog_cd, priority, minutes) values (l_cd, 'ROUTINE', p_routine);
    end if;
  end orderable;
begin
  code_set(71, 'ENCNTR_TYPE', 'Kind of visit, from the patient class in PV1-2');
  code_set(19, 'DISCH_DISP', 'Where the patient went, from PV1-36');
  code_set(220, 'NURSE_UNIT', 'Nursing units, from PV1-3');
  code_set(200, 'ORDERABLE', 'Lab tests that can be ordered, from OBR-4');
  code_set(72, 'EVENT_CODE', 'Result codes, from OBX-3');

  coded(71, 'EMERGENCY', 'Emergency', 'REG', 'E');
  coded(71, 'INPATIENT', 'Inpatient', 'REG', 'I');
  coded(71, 'OUTPATIENT', 'Outpatient', 'REG', 'O');

  coded(19, 'HOME', 'Home or self care', 'REG', '01');
  coded(19, 'TRANSFER_ACUTE', 'Another acute hospital', 'REG', '02');
  coded(19, 'SNF', 'Skilled nursing facility', 'REG', '03');
  coded(19, 'AMA', 'Left against medical advice', 'REG', '07');
  coded(19, 'EXPIRED', 'Died', 'REG', '20');
  coded(19, 'REHAB', 'Inpatient rehabilitation', 'REG', '62');

  unit('ED', 'Emergency department', 'ED', 30);
  unit('4W', '4 West medical', 'WARD', 28);
  unit('5E', '5 East surgical', 'WARD', 24);
  unit('3N', '3 North cardiology', 'WARD', 20);
  unit('ICU', 'Intensive care', 'ICU', 12);

  orderable('CBC', 'Complete blood count', 60, 240);
  orderable('BMP', 'Basic metabolic panel', 60, 240);
  orderable('TROP', 'Troponin I', 60, null);
  orderable('LACT', 'Lactate', 45, null);
  orderable('INR', 'Prothrombin time and INR', 60, 240);

  coded(72, 'WBC', 'White cell count', 'LAB', '6690-2');
  coded(72, 'HGB', 'Haemoglobin', 'LAB', '718-7');
  coded(72, 'PLT', 'Platelets', 'LAB', '777-3');
  coded(72, 'NA', 'Sodium', 'LAB', '2951-2');
  coded(72, 'K', 'Potassium', 'LAB', '2823-3');
  coded(72, 'CREAT', 'Creatinine', 'LAB', '2160-0');
  coded(72, 'GLU', 'Glucose', 'LAB', '2345-7');
  coded(72, 'TROPI', 'Troponin I', 'LAB', '10839-9');
  coded(72, 'LACTATE', 'Lactate', 'LAB', '2524-7');
  coded(72, 'INR', 'INR', 'LAB', '6301-6');
end;
/
