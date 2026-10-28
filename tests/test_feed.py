from collections import defaultdict
from datetime import datetime

from wardround import hl7
from wardround.feed import Feed


def small(seed=1):
    return Feed(seed=seed, start=datetime(2026, 3, 1), days=5, ed_per_day=20, direct_per_day=2)


def event_time(raw):
    return datetime.strptime(hl7.fields_of(raw, "MSH")[7], "%Y%m%d%H%M%S")


def test_same_seed_same_messages():
    assert [o.raw for o in small().messages()] == [o.raw for o in small().messages()]
    assert [o.raw for o in small(2).messages()] != [o.raw for o in small().messages()]


def test_messages_are_in_send_order_and_inside_the_period():
    feed = small()
    out = feed.messages()
    assert out == sorted(out)
    assert all(feed.start <= event_time(o.raw) < feed.end for o in out)


def test_control_ids_are_unique_except_for_resends():
    feed = small()
    seen = defaultdict(set)
    for o in feed.messages():
        seen[(o.source, hl7.fields_of(o.raw, "MSH")[10])].add(o.raw)
    assert all(len(raws) == 1 for raws in seen.values())
    assert len(feed.messages()) - len(seen) == feed.defects["resend"]


def test_each_visit_starts_with_registration_and_ends_with_one_discharge():
    events = defaultdict(list)
    for o in small().messages():
        if o.source == "REG":
            events[hl7.fields_of(o.raw, "PV1")[19]].append(
                (event_time(o.raw), hl7.fields_of(o.raw, "EVN")[1]))
    for visit in events.values():
        kinds = [kind for _, kind in sorted(visit)]
        assert kinds[0] in ("A04", "A01")
        assert kinds.count("A03") <= 1
        assert "A03" not in kinds[:-1]


def test_stat_orders_are_marked_in_obr_27():
    orders = [hl7.fields_of(o.raw, "OBR") for o in small().messages() if o.source == "CPOE"]
    priorities = {obr[27].split("^")[5] for obr in orders}
    assert priorities == {"S", "R"}


def test_defects_go_out_at_the_full_size():
    feed = Feed()
    feed.messages()
    for kind in ("resend", "result_before_order", "order_before_registration",
                 "late_transfer", "unmapped_result"):
        assert feed.defects[kind] > 0, kind
