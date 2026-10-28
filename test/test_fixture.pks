create or replace package test_fixture as
  -- Builds HL7 messages for the tests and sends them through the same
  -- path the feeds use: inbound.receive, then inbound.process.

  type t_fields is table of varchar2(4000) index by pls_integer;

  -- A segment from its fields by number, so f(19) is PV1-19 and so on.
  function seg(p_id varchar2, p_fields t_fields) return varchar2;

  -- An ADT message from registration (REG). p_at is the event time.
  -- Control ids are made up unless given.
  function adt(
    p_event    varchar2,
    p_fin      varchar2,
    p_at       date,
    p_unit     varchar2 default 'ED',
    p_room     varchar2 default null,
    p_bed      varchar2 default null,
    p_class    varchar2 default 'E',
    p_mrn      varchar2 default 'M1',
    p_disp     varchar2 default null,
    p_extra    varchar2 default null,
    p_control  varchar2 default null
  ) return varchar2;

  -- A new lab order (ORM^O01 NW) from order entry (CPOE), or with
  -- p_control_code CA a cancellation.
  function orm(
    p_placer        varchar2,
    p_fin           varchar2,
    p_test          varchar2,
    p_at            date,
    p_stat          boolean default false,
    p_control_code  varchar2 default 'NW',
    p_control       varchar2 default null
  ) return varchar2;

  -- One OBX segment.
  function obx(
    p_n       pls_integer,
    p_loinc   varchar2,
    p_value   varchar2,
    p_units   varchar2 default null,
    p_range   varchar2 default null,
    p_flag    varchar2 default null,
    p_status  varchar2 default 'F'
  ) return varchar2;

  -- Results for an order (ORU^R01) from the lab (LAB); p_obx is OBX
  -- segments from obx, joined with chr(13).
  function oru(
    p_placer     varchar2,
    p_fin        varchar2,
    p_collected  date,
    p_reported   date,
    p_obx        varchar2,
    p_control    varchar2 default null
  ) return varchar2;

  -- Receives a message and processes the queue.
  procedure send(p_raw varchar2);

  -- The status and error of the message with this control id.
  function status_of(p_control varchar2) return varchar2;
  function error_of(p_control varchar2) return varchar2;

  -- The visit with this FIN.
  function visit(p_fin varchar2) return encounters%rowtype;

  -- Its location history as "UNIT from-to" stretches, oldest first, with
  -- times as HH24:MI, e.g. "ED 08:00-10:30, 4W 10:30-".
  function locations(p_fin varchar2) return varchar2;
end test_fixture;
/
