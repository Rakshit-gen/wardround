create or replace package body hl7 as

  -- The p_n-th piece of p_str split on p_sep, counting from 1, or null
  -- past the end. instr rather than regexp, since every separator HL7
  -- uses means something in a regular expression.
  function piece(p_str varchar2, p_sep varchar2, p_n pls_integer) return varchar2 is
    l_start pls_integer := 1;
    l_end   pls_integer;
  begin
    if p_str is null then
      return null;
    end if;
    for i in 1 .. p_n - 1 loop
      l_start := instr(p_str, p_sep, l_start);
      if l_start = 0 then
        return null;
      end if;
      l_start := l_start + 1;
    end loop;
    l_end := instr(p_str, p_sep, l_start);
    if l_end = 0 then
      return substr(p_str, l_start);
    end if;
    return substr(p_str, l_start, l_end - l_start);
  end piece;

  function parse(p_raw clob) return t_message is
    l_msg   t_message;
    l_text  clob;
    l_len   pls_integer;
    l_pos   pls_integer := 1;
    l_end   pls_integer;
    l_seg   varchar2(32767);
    l_n     pls_integer := 0;
  begin
    if p_raw is null or dbms_lob.substr(p_raw, 3, 1) <> 'MSH' or dbms_lob.getlength(p_raw) < 8 then
      raise_application_error(wr_errors.bad_field, 'not an HL7 message: it doesn''t start with MSH');
    end if;
    l_text := replace(replace(p_raw, chr(13) || chr(10), chr(13)), chr(10), chr(13));
    l_len := dbms_lob.getlength(l_text);

    l_msg.field_sep := dbms_lob.substr(l_text, 1, 4);
    l_msg.component_sep := dbms_lob.substr(l_text, 1, 5);
    l_msg.repetition_sep := dbms_lob.substr(l_text, 1, 6);
    l_msg.escape_char := dbms_lob.substr(l_text, 1, 7);
    l_msg.subcomponent_sep := dbms_lob.substr(l_text, 1, 8);

    while l_pos <= l_len loop
      l_end := dbms_lob.instr(l_text, chr(13), l_pos);
      if l_end = 0 then
        l_end := l_len + 1;
      end if;
      if l_end - l_pos > 32767 then
        raise_application_error(wr_errors.bad_field, 'segment ' || (l_n + 1) || ' is longer than 32767 characters');
      end if;
      l_seg := case when l_end > l_pos then dbms_lob.substr(l_text, l_end - l_pos, l_pos) end;
      if trim(l_seg) is not null then
        l_n := l_n + 1;
        l_msg.segments(l_n) := l_seg;
      end if;
      l_pos := l_end + 1;
    end loop;
    return l_msg;
  end parse;

  function find(
    p_msg   t_message,
    p_id    varchar2,
    p_nth   pls_integer default 1,
    p_from  pls_integer default 1
  ) return pls_integer is
    l_seen pls_integer := 0;
  begin
    for i in p_from .. p_msg.segments.count loop
      if substr(p_msg.segments(i), 1, 3) = p_id
         and (length(p_msg.segments(i)) = 3 or substr(p_msg.segments(i), 4, 1) = p_msg.field_sep) then
        l_seen := l_seen + 1;
        if l_seen = p_nth then
          return i;
        end if;
      end if;
    end loop;
    return null;
  end find;

  -- Field p_field of segment p_seg as sent, still escaped.
  function raw_field(p_msg t_message, p_seg pls_integer, p_field pls_integer) return varchar2 is
    l_seg varchar2(32767);
  begin
    if p_seg is null or not p_msg.segments.exists(p_seg) then
      return null;
    end if;
    l_seg := p_msg.segments(p_seg);
    if substr(l_seg, 1, 3) = 'MSH' then
      -- MSH-1 is the separator, so MSH-n is the n-th piece.
      if p_field = 1 then
        return p_msg.field_sep;
      end if;
      return piece(l_seg, p_msg.field_sep, p_field);
    end if;
    return piece(l_seg, p_msg.field_sep, p_field + 1);
  end raw_field;

  function get(
    p_msg           t_message,
    p_seg           pls_integer,
    p_field         pls_integer,
    p_component     pls_integer default 1,
    p_repetition    pls_integer default 1,
    p_subcomponent  pls_integer default 1
  ) return varchar2 is
    l_val varchar2(32767) := raw_field(p_msg, p_seg, p_field);
  begin
    if l_val is null then
      return null;
    end if;
    -- MSH-1 and MSH-2 are the separators themselves.
    if substr(p_msg.segments(p_seg), 1, 3) = 'MSH' and p_field <= 2 then
      return l_val;
    end if;
    l_val := piece(l_val, p_msg.repetition_sep, p_repetition);
    l_val := piece(l_val, p_msg.component_sep, p_component);
    l_val := piece(l_val, p_msg.subcomponent_sep, p_subcomponent);
    return unescape_text(p_msg, l_val);
  end get;

  function val(
    p_msg         t_message,
    p_id          varchar2,
    p_field       pls_integer,
    p_component   pls_integer default 1,
    p_repetition  pls_integer default 1
  ) return varchar2 is
  begin
    return get(p_msg, find(p_msg, p_id), p_field, p_component, p_repetition);
  end val;

  function repetitions(p_msg t_message, p_seg pls_integer, p_field pls_integer) return pls_integer is
    l_val varchar2(32767) := raw_field(p_msg, p_seg, p_field);
  begin
    if l_val is null then
      return 0;
    end if;
    return length(l_val) - nvl(length(replace(l_val, p_msg.repetition_sep)), 0) + 1;
  end repetitions;

  function ts(p_value varchar2) return date is
    l_digits varchar2(14) := regexp_substr(p_value, '^[0-9]{4,14}');
    l_rest   varchar2(32767) := substr(p_value, nvl(length(l_digits), 0) + 1);
  begin
    if p_value is null then
      return null;
    end if;
    if l_digits is null or mod(length(l_digits), 2) = 1
       or l_rest is not null and substr(l_rest, 1, 1) not in ('.', '+', '-') then
      raise_application_error(wr_errors.bad_field, 'not an HL7 date and time: "' || substr(p_value, 1, 40) || '"');
    end if;
    -- Missing parts default to the first month, day, hour and minute.
    return to_date(l_digits || substr('0101000000', length(l_digits) - 3), 'YYYYMMDDHH24MISS');
  exception
    when value_error then
      raise_application_error(wr_errors.bad_field, 'not an HL7 date and time: "' || substr(p_value, 1, 40) || '"');
    -- to_date raises one of the ORA-018xx errors for a month 13 or a
    -- 31st of April; all of them mean the field is bad.
    when others then
      if sqlcode between -1899 and -1800 then
        raise_application_error(wr_errors.bad_field, 'not an HL7 date and time: "' || substr(p_value, 1, 40) || '"');
      end if;
      raise;
  end ts;

  function unescape_text(p_msg t_message, p_value varchar2) return varchar2 is
    l_esc  varchar2(1) := p_msg.escape_char;
    l_out  varchar2(32767);
    l_i    pls_integer := 1;
    l_j    pls_integer;
    l_seq  varchar2(32767);
  begin
    if p_value = '""' then
      return null;
    end if;
    if p_value is null or l_esc is null or instr(p_value, l_esc) = 0 then
      return p_value;
    end if;
    while l_i <= length(p_value) loop
      if substr(p_value, l_i, 1) = l_esc then
        l_j := instr(p_value, l_esc, l_i + 1);
        if l_j = 0 then
          -- An escape that's never closed is kept as sent.
          return l_out || substr(p_value, l_i);
        end if;
        l_seq := substr(p_value, l_i + 1, l_j - l_i - 1);
        l_out := l_out || case l_seq
                            when 'F' then p_msg.field_sep
                            when 'S' then p_msg.component_sep
                            when 'T' then p_msg.subcomponent_sep
                            when 'R' then p_msg.repetition_sep
                            when 'E' then l_esc
                            when '.br' then chr(10)
                            else l_esc || l_seq || l_esc
                          end;
        l_i := l_j + 1;
      else
        l_out := l_out || substr(p_value, l_i, 1);
        l_i := l_i + 1;
      end if;
    end loop;
    return l_out;
  end unescape_text;

  function escape_text(p_value varchar2) return varchar2 is
  begin
    -- The escape character first, so the escapes added after it aren't
    -- escaped again.
    return replace(replace(replace(replace(replace(replace(p_value,
             '\', '\E\'), '|', '\F\'), '^', '\S\'), '&', '\T\'), '~', '\R\'), chr(10), '\.br\');
  end escape_text;

  function ack(
    p_msg         t_message,
    p_code        varchar2,
    p_control_id  varchar2,
    p_text        varchar2 default null
  ) return varchar2 is
    l_msh pls_integer := find(p_msg, 'MSH');
  begin
    -- The ACK goes back the way the message came: its sender is the
    -- message's receiver and the other way round.
    return 'MSH|^~\&|' || nvl(raw_field(p_msg, l_msh, 5), 'WARDROUND') || '|' || raw_field(p_msg, l_msh, 6)
        || '|' || raw_field(p_msg, l_msh, 3) || '|' || raw_field(p_msg, l_msh, 4)
        || '|' || to_char(sysdate, 'YYYYMMDDHH24MISS') || '||ACK^' || get(p_msg, l_msh, 9, 2) || '^ACK'
        || '|' || p_control_id || '|' || nvl(raw_field(p_msg, l_msh, 11), 'P')
        || '|' || nvl(raw_field(p_msg, l_msh, 12), '2.5.1') || chr(13)
        || 'MSA|' || p_code || '|' || raw_field(p_msg, l_msh, 10)
        || case when p_text is not null then '|' || escape_text(substr(p_text, 1, 200)) end || chr(13);
  end ack;
end hl7;
/
