"""OpenStreetMap `opening_hours` → the weekday lines the place page shows.

The app renders Google's style ("Monday: 11:00 AM – 11:00 PM"). OSM writes
"Mo-Fr 09:00-18:00; Sa 10:00-14:00; Su off". Only the common shapes are
understood (day ranges / lists, one or more time ranges, off, 24/7); anything
else returns None and the caller shows the raw text instead.
"""
from __future__ import annotations

import re
from typing import Optional

_DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
_DAY = r"(?:Mo|Tu|We|Th|Fr|Sa|Su|PH)"
_RULE = re.compile(rf"^({_DAY}(?:\s*[-,]\s*{_DAY})*)\s+(.+)$")
_RANGE = re.compile(r"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})")


def _clock(h: int, m: int) -> str:
    h %= 24
    suffix = "AM" if h < 12 else "PM"
    h12 = h % 12 or 12
    return f"{h12}:{m:02d} {suffix}"


def _days(part: str) -> Optional[list[int]]:
    out: list[int] = []
    for piece in part.split(","):
        piece = piece.strip()
        if piece == "PH":
            continue
        if "-" in piece:
            a, b = [x.strip() for x in piece.split("-", 1)]
            if a not in _DAYS or b not in _DAYS:
                return None
            i, j = _DAYS.index(a), _DAYS.index(b)
            out += list(range(i, j + 1)) if i <= j else list(range(i, 7)) + list(range(0, j + 1))
        elif piece in _DAYS:
            out.append(_DAYS.index(piece))
        else:
            return None
    return out


def to_weekday_lines(spec: Optional[str]) -> Optional[list[str]]:
    s = (spec or "").strip()
    if not s:
        return None
    if s == "24/7":
        return [f"{n}: Open 24 hours" for n in _NAMES]
    table: dict[int, str] = {}
    for rule in s.split(";"):
        rule = rule.strip()
        if not rule:
            continue
        m = _RULE.match(rule)
        if m:
            days, times = _days(m.group(1)), m.group(2).strip()
        elif re.match(r"^\d{1,2}:\d{2}", rule):
            days, times = list(range(7)), rule
        else:
            return None
        if days is None:
            return None
        if times.lower() in ("off", "closed"):
            value = "Closed"
        else:
            ranges = _RANGE.findall(times)
            if not ranges:
                return None
            value = ", ".join(
                f"{_clock(int(h1), int(m1))} – {_clock(int(h2), int(m2))}"
                for h1, m1, h2, m2 in ranges
            )
        for d in days:
            table[d] = value
    if not table:
        return None
    return [f"{_NAMES[d]}: {table.get(d, 'Closed')}" for d in range(7)]
