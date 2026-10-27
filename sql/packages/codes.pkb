create or replace package body codes as

  type t_cache is table of number index by varchar2(200);
  type t_meanings is table of varchar2(30) index by pls_integer;
  g_aliases   t_cache;
  g_meanings  t_cache;
  g_by_cd     t_meanings;

  function lookup(p_set number, p_source varchar2, p_alias varchar2) return number is
    l_key varchar2(200) := p_set || '|' || p_source || '|' || p_alias;
  begin
    if p_alias is null then
      return null;
    end if;
    if not g_aliases.exists(l_key) then
      select code_value into g_aliases(l_key)
        from code_value_aliases
       where code_set = p_set and source = p_source and alias = p_alias;
    end if;
    return g_aliases(l_key);
  exception
    when no_data_found then
      raise_application_error(wr_errors.unmapped_code,
        p_source || ' code "' || p_alias || '" isn''t mapped in code set ' || p_set);
  end lookup;

  function cd(p_set number, p_meaning varchar2) return number is
    l_key varchar2(200) := p_set || '|' || p_meaning;
  begin
    if not g_meanings.exists(l_key) then
      select code_value into g_meanings(l_key)
        from code_values
       where code_set = p_set and meaning = p_meaning;
    end if;
    return g_meanings(l_key);
  exception
    when no_data_found then
      raise_application_error(wr_errors.unmapped_code,
        'code set ' || p_set || ' has no value meaning ' || p_meaning);
  end cd;

  function meaning(p_cd number) return varchar2 is
  begin
    if p_cd is null then
      return null;
    end if;
    if not g_by_cd.exists(p_cd) then
      select meaning into g_by_cd(p_cd) from code_values where code_value = p_cd;
    end if;
    return g_by_cd(p_cd);
  exception
    when no_data_found then
      return null;
  end meaning;

  procedure reset is
  begin
    g_aliases.delete;
    g_meanings.delete;
    g_by_cd.delete;
  end reset;
end codes;
/
