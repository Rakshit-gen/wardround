create or replace package body test_codes as

  procedure lookup_found is
  begin
    ut.expect(codes.lookup(220, 'REG', '4W')).to_equal(codes.cd(220, '4W'));
    ut.expect(codes.meaning(codes.lookup(72, 'LAB', '6690-2'))).to_equal('WBC');
    ut.expect(codes.lookup(220, 'REG', null)).to_be_null();
  end lookup_found;

  procedure lookup_unmapped is
    l_cd number := codes.lookup(72, 'LAB', '2093-3');
  begin
    null;
  end lookup_unmapped;

  procedure map_new_value is
    l_display code_values.display%type;
  begin
    codes.map_alias(72, 'LAB', '2093-3', 'CHOL', 'Cholesterol');
    select display into l_display from code_values where code_set = 72 and meaning = 'CHOL';
    ut.expect(l_display).to_equal('Cholesterol');
    ut.expect(codes.lookup(72, 'LAB', '2093-3')).to_equal(codes.cd(72, 'CHOL'));
  end map_new_value;

  procedure map_existing_value is
    l_values pls_integer;
  begin
    codes.map_alias(220, 'REG', '4WEST', '4W');
    codes.map_alias(220, 'REG', '4WEST', '4W');
    select count(*) into l_values from code_values where code_set = 220 and meaning = '4W';
    ut.expect(l_values).to_equal(1);
    ut.expect(codes.lookup(220, 'REG', '4WEST')).to_equal(codes.cd(220, '4W'));
  end map_existing_value;

  procedure map_conflict is
  begin
    codes.map_alias(220, 'REG', '4W', '5E');
  end map_conflict;
end test_codes;
/
