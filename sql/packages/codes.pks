create or replace package codes as
  -- Looks up code values. Found lookups are cached for the session;
  -- misses aren't, so an alias mapped after a message failed is found
  -- when the message is reprocessed.

  -- The code value p_source's code p_alias maps to in code set p_set.
  -- Null for a null alias; raises unmapped_code if there's no mapping.
  function lookup(p_set number, p_source varchar2, p_alias varchar2) return number;

  -- The code value with meaning p_meaning in code set p_set. Raises
  -- unmapped_code if there isn't one, which means the reference data is
  -- missing a row.
  function cd(p_set number, p_meaning varchar2) return number;

  -- The meaning of a code value, or null.
  function meaning(p_cd number) return varchar2;

  -- Maps p_source's code p_alias to the value with meaning p_meaning in
  -- code set p_set, adding the value (shown as p_display) if the set
  -- doesn't have it. What an interface analyst does when a message fails
  -- on a code nobody mapped; the message can be reprocessed after.
  -- Raises out_of_step if the alias already maps to a different value.
  -- Doesn't commit.
  procedure map_alias(
    p_set      number,
    p_source   varchar2,
    p_alias    varchar2,
    p_meaning  varchar2,
    p_display  varchar2 default null
  );

  -- Forgets the cache, for after a mapping changes.
  procedure reset;
end codes;
/
