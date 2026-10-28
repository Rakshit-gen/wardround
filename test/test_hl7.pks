create or replace package test_hl7 as
  --%suite(hl7: reading and writing messages)

  --%test(CR, LF and CRLF all end a segment)
  procedure line_endings;

  --%test(Something that doesn't start with MSH is refused)
  --%throws(-20003)
  procedure not_hl7;

  --%test(MSH fields are numbered with the separator as MSH-1)
  procedure msh_numbering;

  --%test(Components, repetitions and subcomponents are read by number)
  procedure parts;

  --%test(A missing segment, field or component is null)
  procedure missing;

  --%test(Two double quotes mean the value was deleted, so it reads as null)
  procedure deleted_value;

  --%test(Escapes are turned back into the characters they stand for)
  procedure unescape;

  --%test(Escaping and unescaping text gives it back)
  procedure escape_round_trip;

  --%test(find counts segments of one kind and can start part way)
  procedure find_nth;

  --%test(Times can have 4 to 14 digits, then fractions or an offset)
  procedure times;

  --%test(A time with an odd number of digits is refused)
  --%throws(-20003)
  procedure odd_time;

  --%test(A 31st of April is refused)
  --%throws(-20003)
  procedure impossible_date;

  --%test(An ACK goes back to the sender and quotes its control id)
  procedure ack;
end test_hl7;
/
