create or replace package test_codes as
  --%suite(codes: code values and the aliases feeds use)

  --%test(lookup finds a feed's code and caches it)
  procedure lookup_found;

  --%test(lookup of a code nobody mapped raises unmapped_code)
  --%throws(-20002)
  procedure lookup_unmapped;

  --%test(map_alias adds the value if the set doesn't have it)
  procedure map_new_value;

  --%test(map_alias to a value that exists adds only the alias, and twice is fine)
  procedure map_existing_value;

  --%test(map_alias won't move an alias to a different value)
  --%throws(-20004)
  procedure map_conflict;
end test_codes;
/
