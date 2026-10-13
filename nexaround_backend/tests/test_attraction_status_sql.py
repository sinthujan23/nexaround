"""The status rules that live in SQL.

Compiled rather than run (there is no database in the test container). The
regressions worth catching: a nearby query that forgets the live filter, a
seed lookup that prefers a hidden row over the live one at the same spot, and
an admin list without a stable order.
"""
import asyncio

from sqlalchemy.dialects import postgresql

from app.repositories.attraction_repository import AttractionRepository


class _Capture:
    def __init__(self):
        self.statements = []

    async def execute(self, stmt, *args, **kwargs):
        self.statements.append(stmt)

        class _R:
            def all(self_inner):
                return []

            def scalars(self_inner):
                class _S:
                    def all(s):
                        return []
                return _S()
        return _R()

    async def scalar(self, stmt):
        self.statements.append(stmt)
        return 0


def _compiled(stmt):
    c = stmt.compile(dialect=postgresql.dialect())
    return str(c), c.params


def _where(sql: str) -> str:
    """The WHERE clause onwards; the column list names every column."""
    return sql.split("WHERE", 1)[1]


def _run(coro):
    return asyncio.run(coro)


def test_nearby_is_live_only_by_default():
    db = _Capture()
    _run(AttractionRepository(db).get_nearby(6.9, 79.8, 1000.0))
    sql, params = _compiled(db.statements[-1])
    assert "attractions.status = " in _where(sql)
    assert "live" in params.values()


def test_nearby_everything_when_asked():
    db = _Capture()
    _run(AttractionRepository(db).get_nearby(6.9, 79.8, 1000.0, visible_only=False))
    sql, _ = _compiled(db.statements[-1])
    assert "attractions.status" not in _where(sql)


def test_search_by_name_is_live_only():
    db = _Capture()
    _run(AttractionRepository(db).search_by_name("fort", 6.9, 79.8))
    sql, params = _compiled(db.statements[-1])
    assert "attractions.status = " in _where(sql) and "live" in params.values()


def test_seed_lookups_prefer_live_and_fetch_tombstones():
    db = _Capture()
    by_gid, by_coord, tombstones = _run(AttractionRepository(db).find_existing_for_seed(
        min_lat=6.9, min_lng=79.8, max_lat=6.91, max_lng=79.81,
        google_place_ids=["ChIJx"],
    ))
    assert tombstones == []
    gid_sql, _ = _compiled(db.statements[0])
    coord_sql, _ = _compiled(db.statements[1])
    tomb_sql, tomb_params = _compiled(db.statements[2])
    assert "ORDER BY attractions.is_active DESC" in gid_sql
    assert "ORDER BY attractions.is_active DESC" in coord_sql
    assert "attractions.status IN" in _where(tomb_sql)
    assert {"hidden", "rejected"} <= set(
        v for vals in tomb_params.values() for v in (vals if isinstance(vals, list) else [vals])
    )


def test_admin_list_filters_status_and_orders_stably():
    db = _Capture()
    _run(AttractionRepository(db).admin_list(status="pending", sort="queue", q="fort"))
    sql, params = _compiled(db.statements[-1])
    assert "attractions.status = " in _where(sql) and "pending" in params.values()
    order = sql.split("ORDER BY", 1)[1]
    # user suggestions first, then oldest, then id as the tiebreaker
    assert "attractions.source != " in order
    assert order.index("attractions.created_at") < order.index("attractions.id")
    assert "ILIKE" in sql.upper()


def test_status_counts_group_by_status():
    db = _Capture()
    counts = _run(AttractionRepository(db).status_counts())
    assert counts == {"live": 0, "pending": 0, "hidden": 0, "rejected": 0}
    sql, _ = _compiled(db.statements[-1])
    assert "GROUP BY attractions.status" in sql
