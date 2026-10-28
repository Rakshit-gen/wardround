create or replace package body test_hl7 as

  c_msg constant varchar2(400) :=
    'MSH|^~\&|LAB|HOSP|WARDROUND|HOSP|20260301101500||ORU^R01^ORU_R01|C42|P|2.5.1' || chr(13)
    || 'PID|1||A1^^^OTHER^PI~M7^^^HOSP^MR||DOE^JANE^Q||19800101|F' || chr(13)
    || 'OBX|1|NM|6690-2^WBC^LN||7.2|10*3/uL|4.0-11.0|N|||F' || chr(13)
    || 'OBX|2|ST|X^Note^L||a\F\b\S\c\T\d\R\e\E\f\.br\g\Z\|||""|||F';

  procedure line_endings is
    l_cr hl7.t_message := hl7.parse('MSH|^~\&|A' || chr(13) || 'PID|1' || chr(13) || 'PV1|1');
    l_lf hl7.t_message := hl7.parse('MSH|^~\&|A' || chr(10) || 'PID|1' || chr(10) || 'PV1|1');
    l_crlf hl7.t_message := hl7.parse('MSH|^~\&|A' || chr(13) || chr(10) || 'PID|1' || chr(13) || chr(10) || 'PV1|1' || chr(13) || chr(10));
  begin
    ut.expect(l_cr.segments.count).to_equal(3);
    ut.expect(l_lf.segments.count).to_equal(3);
    ut.expect(l_crlf.segments.count).to_equal(3);
    ut.expect(l_crlf.segments(3)).to_equal('PV1|1');
  end line_endings;

  procedure not_hl7 is
    l_msg hl7.t_message := hl7.parse('PID|1||M1');
  begin
    null;
  end not_hl7;

  procedure msh_numbering is
    l_msg hl7.t_message := hl7.parse(c_msg);
  begin
    ut.expect(hl7.val(l_msg, 'MSH', 3)).to_equal('LAB');
    ut.expect(hl7.val(l_msg, 'MSH', 7)).to_equal('20260301101500');
    ut.expect(hl7.val(l_msg, 'MSH', 9, 1)).to_equal('ORU');
    ut.expect(hl7.val(l_msg, 'MSH', 9, 2)).to_equal('R01');
    ut.expect(hl7.val(l_msg, 'MSH', 10)).to_equal('C42');
    ut.expect(l_msg.field_sep).to_equal('|');
    ut.expect(l_msg.component_sep).to_equal('^');
    ut.expect(l_msg.repetition_sep).to_equal('~');
    ut.expect(l_msg.escape_char).to_equal('\');
    ut.expect(l_msg.subcomponent_sep).to_equal('&');
  end msh_numbering;

  procedure parts is
    l_msg hl7.t_message := hl7.parse(c_msg || chr(13) || 'ZZZ|a&b^c');
    l_pid pls_integer := hl7.find(l_msg, 'PID');
  begin
    ut.expect(hl7.repetitions(l_msg, l_pid, 3)).to_equal(2);
    ut.expect(hl7.get(l_msg, l_pid, 3, 1, 2)).to_equal('M7');
    ut.expect(hl7.get(l_msg, l_pid, 3, 5, 2)).to_equal('MR');
    ut.expect(hl7.val(l_msg, 'PID', 5, 2)).to_equal('JANE');
    ut.expect(hl7.get(l_msg, hl7.find(l_msg, 'ZZZ'), 1, 1, 1, 2)).to_equal('b');
    ut.expect(hl7.get(l_msg, hl7.find(l_msg, 'ZZZ'), 1, 2)).to_equal('c');
  end parts;

  procedure missing is
    l_msg hl7.t_message := hl7.parse(c_msg);
  begin
    ut.expect(hl7.val(l_msg, 'PV1', 19)).to_be_null();
    ut.expect(hl7.val(l_msg, 'PID', 30)).to_be_null();
    ut.expect(hl7.val(l_msg, 'PID', 5, 9)).to_be_null();
    ut.expect(hl7.get(l_msg, 99, 1)).to_be_null();
    ut.expect(hl7.repetitions(l_msg, hl7.find(l_msg, 'PID'), 4)).to_equal(0);
  end missing;

  procedure deleted_value is
    l_msg hl7.t_message := hl7.parse(c_msg);
  begin
    ut.expect(hl7.get(l_msg, hl7.find(l_msg, 'OBX', 2), 8)).to_be_null();
  end deleted_value;

  procedure unescape is
    l_msg hl7.t_message := hl7.parse(c_msg);
  begin
    ut.expect(hl7.get(l_msg, hl7.find(l_msg, 'OBX', 2), 5))
      .to_equal('a|b^c&d~e\f' || chr(10) || 'g\Z\');
  end unescape;

  procedure escape_round_trip is
    l_text varchar2(100) := 'K 3.1 | recheck ^ & ~ \ done' || chr(10) || 'line 2';
    l_msg hl7.t_message := hl7.parse('MSH|^~\&|A' || chr(13) || 'NTE|1||' || hl7.escape_text(l_text));
  begin
    ut.expect(hl7.val(l_msg, 'NTE', 3)).to_equal(l_text);
  end escape_round_trip;

  procedure find_nth is
    l_msg hl7.t_message := hl7.parse(c_msg);
  begin
    ut.expect(hl7.find(l_msg, 'OBX')).to_equal(3);
    ut.expect(hl7.find(l_msg, 'OBX', 2)).to_equal(4);
    ut.expect(hl7.find(l_msg, 'OBX', 3)).to_be_null();
    ut.expect(hl7.find(l_msg, 'OBX', 1, 4)).to_equal(4);
    ut.expect(hl7.find(l_msg, 'OB')).to_be_null();
  end find_nth;

  procedure times is
  begin
    ut.expect(hl7.ts('2026')).to_equal(date '2026-01-01');
    ut.expect(hl7.ts('202603')).to_equal(date '2026-03-01');
    ut.expect(hl7.ts('20260315')).to_equal(date '2026-03-15');
    ut.expect(hl7.ts('202603151042')).to_equal(to_date('2026-03-15 10:42', 'YYYY-MM-DD HH24:MI'));
    ut.expect(hl7.ts('20260315104259.1234+0530')).to_equal(to_date('2026-03-15 10:42:59', 'YYYY-MM-DD HH24:MI:SS'));
    ut.expect(hl7.ts('20260315104259-0500')).to_equal(to_date('2026-03-15 10:42:59', 'YYYY-MM-DD HH24:MI:SS'));
    ut.expect(hl7.ts(null)).to_be_null();
  end times;

  procedure odd_time is
    l_at date := hl7.ts('2026031');
  begin
    null;
  end odd_time;

  procedure impossible_date is
    l_at date := hl7.ts('20260431');
  begin
    null;
  end impossible_date;

  procedure ack is
    l_ack hl7.t_message := hl7.parse(hl7.ack(hl7.parse(c_msg), 'AE', 'WR9', 'bad | text'));
  begin
    ut.expect(hl7.val(l_ack, 'MSH', 3)).to_equal('WARDROUND');
    ut.expect(hl7.val(l_ack, 'MSH', 5)).to_equal('LAB');
    ut.expect(hl7.val(l_ack, 'MSH', 9, 1)).to_equal('ACK');
    ut.expect(hl7.val(l_ack, 'MSH', 9, 2)).to_equal('R01');
    ut.expect(hl7.val(l_ack, 'MSH', 10)).to_equal('WR9');
    ut.expect(hl7.val(l_ack, 'MSA', 1)).to_equal('AE');
    ut.expect(hl7.val(l_ack, 'MSA', 2)).to_equal('C42');
    ut.expect(hl7.val(l_ack, 'MSA', 3)).to_equal('bad | text');
  end ack;

  procedure dashed_date is
    l_at date := hl7.ts('2026-03-02');
  begin
    null;
  end dashed_date;
end test_hl7;
/
