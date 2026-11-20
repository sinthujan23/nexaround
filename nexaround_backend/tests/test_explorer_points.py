"""Explorer Points: levels, scoring and the explainer (TL, 2026-11-20).

Pure rules plus a fake Redis only: the suite runs against the production
database, so nothing here writes a row.
"""
import asyncio

import pytest

from app.services import explorer_points as ep


# ── Ladder ──────────────────────────────────────────────────────────────────

def test_ladder_has_ten_short_rising_levels():
    assert len(ep.LEVELS) == 10 == ep.MAX_LEVEL
    needs = [need for _, need, _ in ep.LEVELS]
    assert needs[0] == 0 and needs == sorted(needs) and len(set(needs)) == 10
    # Short enough for "Lv 5 · Pirate" next to a reviewer's name.
    assert all(len(name) <= 10 for name, _, _ in ep.LEVELS)
    assert len(ep.BADGES) == 10 and all(ep.BADGES)


@pytest.mark.parametrize("points,level", [
    (0, 1), (14, 1), (15, 2), (49, 2), (50, 3), (249, 4), (250, 5),
    (7999, 9), (8000, 10), (10 ** 6, 10), (-5, 1),
])
def test_level_boundaries(points, level):
    assert ep.level_number(points) == level
    assert ep.level_for(points).level == level


def test_progress_and_points_to_next():
    lv = ep.level_for(185)                      # Snaphawk, 120..250
    assert (lv.name, lv.next_name) == ("Snaphawk", "Pirate")
    assert lv.points_to_next == 65
    assert lv.progress == pytest.approx(0.5)
    top = ep.level_for(9000)
    assert top.next_level is None and top.points_to_next == 0 and top.progress == 1.0


# ── Scoring ─────────────────────────────────────────────────────────────────

def test_review_points_grow_with_the_text():
    assert ep.review_points(5, None) == 2
    assert ep.review_points(5, "   nice   ") == 2
    assert ep.review_points(4, "x" * 29) == 2
    assert ep.review_points(4, "x" * 30) == 10
    assert ep.review_points(4, "x" * 199) == 10
    assert ep.review_points(4, "x" * 200) == 20
    assert ep.review_points(0, "x" * 300) == 0


def test_photos_beat_reviews_and_trailblazers_beat_both():
    assert ep.photo_points(False) == 15
    assert ep.photo_points(True) == 25
    assert ep.photo_points(False) > ep.review_points(5, "x" * 30)


def test_totals_add_up():
    t = ep.Totals(ratings=3, written=2, detailed=1, photos=2, trailblazers=1,
                  photos_pending=1, pending_trailblazers=1, odysseys=1, mini_tours=2,
                  bonus=40)
    assert t.review_points == 3 * 2 + 2 * 8 + 1 * 10
    assert t.photo_points == 2 * 15 + 10
    assert t.trip_points == 25 + 2 * 10
    assert t.total == 32 + 40 + 45 + 40
    assert t.pending_points == 25
    # Survives the cache round trip.
    assert ep.Totals(**t.as_cache()).total == t.total


def test_carry_over_only_tops_up_to_the_old_xp():
    assert ep.carry_over_points(120, 0) == 120
    assert ep.carry_over_points(120, 50) == 70      # trips already counted
    assert ep.carry_over_points(120, 500) == 0
    assert ep.carry_over_points(5000, 0) == ep.CARRY_OVER_CAP
    assert ep.carry_over_points(0, 0) == 0


def test_change_block():
    c = ep.change(10, 20)
    assert c == {"earned": 10, "total": 20, "level": 2, "level_name": "Sniffer",
                 "levelled_up": True}
    assert ep.change(20, 20)["levelled_up"] is False
    assert ep.change(30, 10)["earned"] == -20


# ── Explainer and summary ───────────────────────────────────────────────────

def test_info_is_complete():
    info = ep.info()
    assert info["title"] and info["intro"] and info["rules"]
    assert [lv["level"] for lv in info["levels"]] == list(range(1, 11))
    keys = {row["key"]: row["points"] for row in info["earn"]}
    assert keys["rating"] == ep.RATING and keys["photo"] == ep.PHOTO
    assert keys["trailblazer"] == ep.TRAILBLAZER


def test_summary_shape():
    s = ep.summary(ep.Totals(ratings=1, photos_pending=1))
    assert s["total"] == 2 and s["level"]["name"] == "Sofanaut"
    assert s["pending_points"] == 15
    assert s["counts"]["photos_pending"] == 1
    assert set(s["points_by"]) == {"reviews", "photos", "trips", "bonus"}


# ── Level-up messages ───────────────────────────────────────────────────────

class _FakeRedis:
    def __init__(self):
        self.data = {}

    async def get(self, k):
        return self.data.get(k)

    async def set(self, k, v, ex=None):
        self.data[k] = str(v)


def test_level_up_is_announced_once(monkeypatch):
    fake = _FakeRedis()
    sent = []
    monkeypatch.setattr(ep, "_r", lambda: fake)

    async def _notify(uid, title, body):
        sent.append(title)
    monkeypatch.setattr(ep, "notify", _notify)

    async def run():
        await ep.notify_level_up("u1", 10, 20)       # 1 -> 2
        await ep.notify_level_up("u1", 10, 20)       # hidden + restored: no repeat
        await ep.notify_level_up("u1", 20, 21)       # same level
        await ep.notify_level_up("u1", 20, 60)       # 2 -> 3
    asyncio.run(run())
    assert sent == ["Level up! You're now a Sniffer", "Level up! You're now a Snackster"]
