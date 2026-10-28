from datetime import datetime

from wardround import hl7


def test_escape_covers_every_separator():
    assert hl7.escape("a|b^c&d~e\\f\ng") == "a\\F\\b\\S\\c\\T\\d\\R\\e\\E\\f\\.br\\g"


def test_escape_does_not_escape_its_own_escapes():
    assert hl7.escape("\\F\\") == "\\E\\F\\E\\"


def test_segment_numbers_fields():
    assert hl7.segment("PV1", {1: "1", 3: "4W^401^A", 19: "F1"}) == (
        "PV1|1||4W^401^A" + "|" * 16 + "F1"
    )
    assert hl7.segment("NTE", {}) == "NTE"


def test_msh_and_fields_of_agree_on_numbering():
    raw = hl7.message(
        hl7.msh("REG", "ADT^A01^ADT_A01", datetime(2026, 3, 2, 8, 0), "C1"),
        hl7.segment("PV1", {19: "F1"}),
    )
    msh = hl7.fields_of(raw, "MSH")
    assert msh[1] == "|"
    assert msh[3] == "REG"
    assert msh[7] == "20260302080000"
    assert msh[9] == "ADT^A01^ADT_A01"
    assert msh[10] == "C1"
    assert hl7.fields_of(raw, "PV1")[19] == "F1"
    assert hl7.fields_of(raw, "OBX") is None


def test_ack_code():
    assert hl7.ack_code("MSH|^~\\&|WARDROUND\rMSA|AE|C1|bad\r") == "AE"
    assert hl7.ack_code("MSH|^~\\&|WARDROUND\n") is None
