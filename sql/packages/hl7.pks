create or replace package hl7 as
  -- Reads and writes HL7 v2 messages.
  --
  -- A message is segments separated by carriage returns; a segment is
  -- fields separated by the field separator (usually |), and a field can
  -- hold repetitions (~), components (^) and subcomponents (&). The
  -- message says which characters it uses, in MSH-1 and MSH-2, so they're
  -- read from it rather than assumed. Fields are numbered the way the
  -- standard numbers them: PID-3 is the third field after "PID", and in
  -- MSH, where the separator itself is MSH-1, MSH-3 is the second field
  -- after "MSH".

  type t_segments is table of varchar2(32767) index by pls_integer;

  type t_message is record (
    segments          t_segments,
    field_sep         varchar2(1),
    component_sep     varchar2(1),
    repetition_sep    varchar2(1),
    escape_char       varchar2(1),
    subcomponent_sep  varchar2(1)
  );

  -- Splits a message into segments. CR, LF and CRLF all end a segment,
  -- since files and some senders use LF. Raises bad_field if it doesn't
  -- start with MSH.
  function parse(p_raw clob) return t_message;

  -- The index of the p_nth segment called p_id, looking from segment
  -- p_from on, or null if there isn't one.
  function find(
    p_msg   t_message,
    p_id    varchar2,
    p_nth   pls_integer default 1,
    p_from  pls_integer default 1
  ) return pls_integer;

  -- A value from segment number p_seg, unescaped. Null if the segment or
  -- the value isn't there, and for "", which HL7 uses to say a value was
  -- deleted.
  function get(
    p_msg           t_message,
    p_seg           pls_integer,
    p_field         pls_integer,
    p_component     pls_integer default 1,
    p_repetition    pls_integer default 1,
    p_subcomponent  pls_integer default 1
  ) return varchar2;

  -- get from the first segment called p_id.
  function val(
    p_msg         t_message,
    p_id          varchar2,
    p_field       pls_integer,
    p_component   pls_integer default 1,
    p_repetition  pls_integer default 1
  ) return varchar2;

  -- How many repetitions field p_field of segment p_seg has.
  function repetitions(p_msg t_message, p_seg pls_integer, p_field pls_integer) return pls_integer;

  -- An HL7 date and time (YYYY[MM[DD[HH[MM[SS]]]]], then optional
  -- fractions and a UTC offset) as a date. Fractions and the offset are
  -- dropped: the feeds send local time. Raises bad_field if it can't be
  -- read.
  function ts(p_value varchar2) return date;

  -- Turns \F\ \S\ \T\ \R\ \E\ back into the characters they stand for,
  -- and \.br\ into a line break. Other escapes are left as they are.
  function unescape_text(p_msg t_message, p_value varchar2) return varchar2;

  -- Escapes text for a message with the usual separators |^~\&.
  function escape_text(p_value varchar2) return varchar2;

  -- An acknowledgement of p_msg: AA accepted, AE error, AR rejected,
  -- with p_control_id as its own control id and p_text explaining.
  function ack(
    p_msg         t_message,
    p_code        varchar2,
    p_control_id  varchar2,
    p_text        varchar2 default null
  ) return varchar2;
end hl7;
/
