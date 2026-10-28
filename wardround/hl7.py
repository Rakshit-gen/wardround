"""Building and reading HL7 v2 messages, with the usual separators |^~\\&."""

from datetime import datetime

FIELD = "|"
COMPONENT = "^"
REPETITION = "~"
ESCAPE = "\\"
SUBCOMPONENT = "&"

_ESCAPES = [
    (ESCAPE, "\\E\\"),  # first, so the escapes added after it aren't escaped again
    (FIELD, "\\F\\"),
    (COMPONENT, "\\S\\"),
    (SUBCOMPONENT, "\\T\\"),
    (REPETITION, "\\R\\"),
    ("\n", "\\.br\\"),
]


def escape(text: str) -> str:
    for char, seq in _ESCAPES:
        text = text.replace(char, seq)
    return text


def ts(at: datetime) -> str:
    return at.strftime("%Y%m%d%H%M%S")


def segment(seg_id: str, fields: dict[int, str]) -> str:
    """A segment from its fields by number, so {19: "F1"} is PV1-19.

    Values are put in as given: escape free text first. MSH is built by
    msh(), since its numbering is different.
    """
    last = max(fields, default=0)
    return FIELD.join([seg_id] + [fields.get(i, "") or "" for i in range(1, last + 1)])


def msh(sender: str, message_type: str, at: datetime, control_id: str) -> str:
    return FIELD.join(
        [
            "MSH",
            "^~\\&",
            sender,
            "HOSP",
            "WARDROUND",
            "HOSP",
            ts(at),
            "",
            message_type,
            control_id,
            "P",
            "2.5.1",
        ]
    )


def message(*segments: str) -> str:
    return "\r".join(segments)


def fields_of(raw: str, seg_id: str) -> list[str] | None:
    """The fields of the first seg_id segment, numbered so that
    fields_of(raw, "MSA")[1] is MSA-1, or None if there isn't one. MSH is
    numbered the HL7 way too: [1] is the separator, [10] the control id."""
    for seg in raw.replace("\r\n", "\r").replace("\n", "\r").split("\r"):
        parts = seg.split(FIELD)
        if parts[0] == seg_id:
            if seg_id == "MSH":
                return ["MSH", FIELD] + parts[1:]
            return parts
    return None


def ack_code(ack: str) -> str | None:
    """MSA-1 of an ACK: AA, AE or AR."""
    msa = fields_of(ack, "MSA")
    return msa[1] if msa and len(msa) > 1 else None
