"""Merge the duplicate copies the old Google seeder left in `attractions`.

Before 2026-08-26 (commit e374277) the seeder inserted a second, switched-off
row whenever a place already existed at the same spot, "for an admin to
approve". Nobody did, and every visit to an area added another copy. Those
copies are what filled the old Place Approvals page; after the lifecycle
migration they are `pending / legacy_inactive`.

Only live rows and those old copies (`pending / legacy_inactive`) take part.
A row an admin hid or rejected, and a place someone suggested from the app,
is a decision or a request, not a leftover — the script never touches them.

For each group of copies of one place this keeps the best row, moves people's
reviews, photos and visits onto it, fills its blank fields from the copies,
records the copies' ids as aliases (favourites hold place ids), and deletes
the copies. A place whose every copy was switched off comes back live.

Two rows are copies of one place when:
  - they share a Google place id and are within 250 m of each other (a wider
    gap means one id was resolved wrongly; reported, never merged), or
  - they sit on identical coordinates (6 decimals) and one lowercase name
    contains the other — the seeder's own rule, and the exact way the old bug
    laid copies down.

Usage (in the api container, from nexaround_backend/):
    docker compose run --rm -T api python -m app.scripts.merge_duplicate_attractions
    docker compose run --rm -T api python -m app.scripts.merge_duplicate_attractions --apply

Dry run is the default and changes nothing. Plans and logs are written to
app/scripts/merge_logs/ (bind-mounted, so they survive the container).
"""
import argparse
import asyncio
import json
import os
import re
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import text

from app.utils.place_match import SAME_PLACE_M, haversine_m, names_match

GID_MAX_SPREAD_M = 250.0
MERGE_SCRIPT = "merge-script"
LOG_DIR = os.path.join(os.path.dirname(__file__), "merge_logs")

_UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I
)


@dataclass
class Row:
    id: str
    name: str
    gid: Optional[str]
    lat: float
    lng: float
    status: str
    created_at: Optional[datetime] = None
    reason: Optional[str] = None
    photos: int = 0
    has_description: bool = False
    has_history: bool = False
    has_address: bool = False
    has_hours: bool = False
    has_tags: bool = False
    details_fetched: bool = False
    review_count: int = 0
    reviews: int = 0
    media: int = 0
    visits: int = 0

    @property
    def coord(self) -> tuple:
        return (round(self.lat, 6), round(self.lng, 6))


@dataclass
class Group:
    survivor: Row
    losers: list
    status: str
    status_reason: Optional[str]
    via: set = field(default_factory=set)  # "gid" and/or "coord"

    @property
    def members(self) -> list:
        return [self.survivor, *self.losers]


# --- Pure planning -------------------------------------------------------------

class _UnionFind:
    def __init__(self):
        self.parent = {}

    def find(self, x):
        self.parent.setdefault(x, x)
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.parent[rb] = ra


def is_candidate(r: Row) -> bool:
    """Live rows and the old seeder's switched-off copies. Nothing else."""
    return r.status == "live" or (r.status == "pending" and r.reason == "legacy_inactive")


def score(r: Row) -> int:
    """How much a row carries. The survivor should be the richest copy."""
    return (
        (3 if r.gid else 0)
        + min(r.photos, 5)
        + (2 if r.has_description else 0)
        + (2 if r.has_history else 0)
        + (1 if r.has_address else 0)
        + (1 if r.has_hours else 0)
        + (1 if r.has_tags else 0)
        + (3 if (r.reviews or r.media) else 0)
        + (1 if r.details_fetched else 0)
    )


def survivor_key(r: Row) -> tuple:
    """Live first, then richest, then oldest (the id clients most likely hold)."""
    created = r.created_at or datetime.max.replace(tzinfo=timezone.utc)
    return (r.status != "live", -score(r), created, r.id)


def group_status(members: list) -> tuple:
    """(status, reason) for the kept row, from the copies' statuses."""
    statuses = {m.status for m in members}
    if "live" in statuses:
        return "live", None
    # An admin's decision outranks a leftover copy.
    if "rejected" in statuses:
        return "rejected", None
    if "hidden" in statuses:
        return "hidden", None
    return "live", "merged_restored"


def _same_name(a: str, b: str, exact: bool) -> bool:
    if exact:
        return (a or "").strip().lower() == (b or "").strip().lower()
    return names_match(a, b)


def plan_groups(rows: list, *, exact_names_only: bool = False) -> tuple:
    """Group copies of the same place. Returns (groups, report)."""
    uf = _UnionFind()
    via = defaultdict(set)
    report = {"gid_conflicts": [], "differing_names": 0}

    # 1. Same Google id, within GID_MAX_SPREAD_M of the first such row.
    by_gid = defaultdict(list)
    for r in rows:
        if r.gid:
            by_gid[r.gid].append(r)
    for gid, members in by_gid.items():
        if len(members) < 2:
            continue
        members = sorted(members, key=survivor_key)
        anchor = members[0]
        for m in members[1:]:
            d = haversine_m(anchor.lat, anchor.lng, m.lat, m.lng)
            if exact_names_only and not _same_name(anchor.name, m.name, True):
                # Old rows got their Google id from a name lookup, which can
                # land on a neighbour ("The Gardens Mall" for a golf arena
                # inside it). Strict mode trusts the id only with the name.
                continue
            if d <= GID_MAX_SPREAD_M:
                uf.union(anchor.id, m.id)
                via[anchor.id].add("gid")
                via[m.id].add("gid")
            else:
                report["gid_conflicts"].append({
                    "gid": gid,
                    "a": {"id": anchor.id, "name": anchor.name},
                    "b": {"id": m.id, "name": m.name},
                    "distance_m": round(d),
                })

    # 2. Identical coordinates and a matching name. Longest name first, and
    #    each row joins the first representative it matches, so a run of
    #    loosely similar names cannot chain unrelated places together.
    by_coord = defaultdict(list)
    for r in rows:
        by_coord[r.coord].append(r)
    for members in by_coord.values():
        if len(members) < 2:
            continue
        reps = []
        for m in sorted(members, key=lambda r: (-len(r.name or ""), r.id)):
            for rep in reps:
                if _same_name(rep.name, m.name, exact_names_only):
                    uf.union(rep.id, m.id)
                    via[rep.id].add("coord")
                    via[m.id].add("coord")
                    break
            else:
                reps.append(m)

    clusters = defaultdict(list)
    for r in rows:
        if r.id in uf.parent:
            clusters[uf.find(r.id)].append(r)

    groups = []
    for members in clusters.values():
        if len(members) < 2:
            continue
        members.sort(key=survivor_key)
        status, reason = group_status(members)
        g = Group(
            survivor=members[0],
            losers=members[1:],
            status=status,
            status_reason=reason,
            via=set().union(*(via[m.id] for m in members)),
        )
        if len({(m.name or "").strip().lower() for m in members}) > 1:
            report["differing_names"] += 1
        groups.append(g)

    groups.sort(key=lambda g: (g.survivor.lat, g.survivor.lng, g.survivor.id))
    return groups, report


def near_duplicates(rows: list) -> int:
    """Pairs of rows (after merging) under 25 m apart with matching names but
    different coordinates. Reported only: these are judgement calls."""
    cell = 0.0003
    grid = defaultdict(list)
    for r in rows:
        grid[(int(r.lat // cell), int(r.lng // cell))].append(r)
    pairs = 0
    for (cy, cx), members in grid.items():
        for r in members:
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    for o in grid.get((cy + dy, cx + dx), ()):
                        if o.id <= r.id or o.coord == r.coord:
                            continue
                        if (haversine_m(r.lat, r.lng, o.lat, o.lng) < SAME_PLACE_M
                                and names_match(r.name, o.name)):
                            pairs += 1
    return pairs


def _review_conflicts(group: Group, reviewers: dict) -> int:
    """Reviews that would be dropped because one user reviewed two copies."""
    per_user = Counter()
    for m in group.members:
        for uid in reviewers.get(m.id, ()):
            per_user[uid] += 1
    return sum(n - 1 for n in per_user.values() if n > 1)


# --- Database ------------------------------------------------------------------

_LOAD_ROWS = text("""
    SELECT a.id::text, a.name, a.google_place_id,
           ST_Y(a.location), ST_X(a.location), a.status, a.created_at,
           coalesce(array_length(a.photo_urls, 1), 0),
           coalesce(a.description, '') <> '',
           coalesce(a.history, '') <> '',
           coalesce(a.address, '') <> '',
           coalesce(a.opening_hours::text, '{}') NOT IN ('{}', 'null'),
           coalesce(array_length(a.tags, 1), 0) > 0,
           a.details_fetched_at IS NOT NULL,
           coalesce(a.review_count, 0),
           a.status_reason
    FROM attractions a
""")


async def _load(session) -> tuple:
    rows = [
        Row(
            id=r[0], name=r[1] or "", gid=r[2], lat=r[3], lng=r[4],
            status=r[5], created_at=r[6], photos=r[7], has_description=r[8],
            has_history=r[9], has_address=r[10], has_hours=r[11],
            has_tags=r[12], details_fetched=r[13], review_count=r[14],
            reason=r[15],
        )
        for r in (await session.execute(_LOAD_ROWS)).all()
    ]
    by_id = {r.id: r for r in rows}
    for table, attr in (("reviews", "reviews"), ("media", "media"), ("place_visits", "visits")):
        res = await session.execute(text(
            f"SELECT attraction_id::text, count(*) FROM {table} "
            f"WHERE attraction_id IS NOT NULL GROUP BY 1"
        ))
        for aid, n in res.all():
            if aid in by_id:
                setattr(by_id[aid], attr, n)
    reviewers = defaultdict(list)
    for aid, uid in (await session.execute(text(
        "SELECT attraction_id::text, user_id::text FROM reviews"
    ))).all():
        reviewers[aid].append(uid)
    return rows, reviewers


async def _favourite_ids(session) -> Counter:
    """How many users hold each place id in their saved preferences."""
    held = Counter()
    res = await session.execute(text(
        "SELECT preferences::text FROM users WHERE preferences IS NOT NULL"
    ))
    for (prefs,) in res.all():
        for pid in set(m.lower() for m in _UUID_RE.findall(prefs or "")):
            held[pid] += 1
    return held


_FILL_FIELDS = (
    "google_place_id", "photo_urls", "description", "history", "address",
    "opening_hours", "tags", "category_id",
)


def _uuids(ids) -> list:
    return [uuid.UUID(i) for i in ids]


def _blank(value) -> bool:
    return value in (None, "", [], {}) or (isinstance(value, str) and not value.strip())


async def _apply_group(session, g: Group) -> Optional[dict]:
    ids = [m.id for m in g.members]
    loser_ids = [m.id for m in g.losers]
    full = {
        str(r["id"]): r
        for r in (await session.execute(text("""
            SELECT id, google_place_id, photo_urls, description, history, address,
                   opening_hours, tags, category_id, details_fetched_at,
                   rating, review_count
            FROM attractions WHERE id = ANY(CAST(:ids AS uuid[]))
            FOR UPDATE
        """), {"ids": _uuids(ids)})).mappings().all()
    }
    if g.survivor.id not in full:
        return None  # removed since the plan was made
    present_losers = [i for i in loser_ids if i in full]
    if not present_losers:
        return None

    survivor = full[g.survivor.id]
    ordered = [full[m.id] for m in g.members if m.id in full]

    updates = {}
    gids = {r["google_place_id"] for r in ordered if r["google_place_id"]}
    for f in _FILL_FIELDS:
        if not _blank(survivor[f]):
            continue
        if f == "google_place_id":
            if len(gids) == 1:
                updates[f] = next(iter(gids))
            continue
        for r in ordered[1:]:
            if not _blank(r[f]):
                updates[f] = r[f]
                break
    fetched = [r["details_fetched_at"] for r in ordered if r["details_fetched_at"]]
    if fetched and max(fetched) != survivor["details_fetched_at"]:
        updates["details_fetched_at"] = max(fetched)
    # Google's rating and count: the copy with the most reviews is the
    # freshest (the old seeder wrote new counts into the copies).
    best = max(ordered, key=lambda r: r["review_count"] or 0)
    if (best["review_count"] or 0) > (survivor["review_count"] or 0):
        updates["review_count"] = best["review_count"]
        updates["rating"] = best["rating"]

    # One review per user per place: where a user reviewed several copies,
    # keep their newest. Otherwise POST /reviews, which looks a user's review
    # up with scalar_one_or_none, would fail for them.
    dropped_reviews = (await session.execute(text("""
        DELETE FROM reviews r USING (
            SELECT id, row_number() OVER (
                PARTITION BY user_id ORDER BY created_at DESC NULLS LAST, id DESC
            ) AS rn
            FROM reviews WHERE attraction_id = ANY(CAST(:ids AS uuid[]))
        ) d
        WHERE r.id = d.id AND d.rn > 1
    """), {"ids": _uuids(ids)})).rowcount

    s_id, l_ids = uuid.UUID(g.survivor.id), _uuids(present_losers)
    moved = {}
    for table in ("reviews", "media", "place_visits"):
        moved[table] = (await session.execute(text(
            f"UPDATE {table} SET attraction_id = CAST(:s AS uuid) "
            f"WHERE attraction_id = ANY(CAST(:l AS uuid[]))"
        ), {"s": s_id, "l": l_ids})).rowcount

    await session.execute(text(
        "UPDATE attraction_aliases SET attraction_id = CAST(:s AS uuid) "
        "WHERE attraction_id = ANY(CAST(:l AS uuid[]))"
    ), {"s": s_id, "l": l_ids})
    await session.execute(text("""
        INSERT INTO attraction_aliases (old_id, attraction_id)
        SELECT unnest(CAST(:l AS uuid[])), CAST(:s AS uuid)
        ON CONFLICT (old_id) DO UPDATE SET attraction_id = EXCLUDED.attraction_id
    """), {"s": s_id, "l": l_ids})

    deleted = (await session.execute(text(
        "DELETE FROM attractions WHERE id = ANY(CAST(:l AS uuid[]))"
    ), {"l": l_ids})).rowcount

    status_changed = g.survivor.status != g.status
    sets = dict(updates)
    if status_changed:
        sets.update(
            status=g.status,
            status_reason=g.status_reason,
            reviewed_at=datetime.now(timezone.utc),
            reviewed_by=MERGE_SCRIPT,
        )
    if sets:
        sets["updated_at"] = datetime.now(timezone.utc)
        assignments = ", ".join(
            f"{k} = CAST(:{k} AS json)" if k == "opening_hours" else f"{k} = :{k}"
            for k in sets
        )
        params = dict(sets)
        if "opening_hours" in params:
            params["opening_hours"] = json.dumps(params["opening_hours"])
        params["id"] = s_id
        await session.execute(
            text(f"UPDATE attractions SET {assignments} WHERE id = CAST(:id AS uuid)"),
            params,
        )

    return {
        "survivor": g.survivor.id,
        "deleted": deleted,
        "losers": present_losers,
        "filled": sorted(k for k in updates if k not in ("rating", "review_count")),
        "status": g.status if status_changed else None,
        "dropped_reviews": dropped_reviews,
        "moved": moved,
    }


def _row_json(r: Row) -> dict:
    return {
        "id": r.id, "name": r.name, "status": r.status, "gid": r.gid,
        "lat": r.lat, "lng": r.lng, "score": score(r),
        "created_at": r.created_at.isoformat() if r.created_at else None,
        "reviews": r.reviews, "media": r.media, "visits": r.visits,
    }


def _print_report(rows, groups, report, reviewers, favourites, singles, near, samples):
    by_status = Counter(r.status for r in rows)
    losers = [m for g in groups for m in g.losers]
    print("\n=== attractions by status ===")
    for s in ("live", "pending", "hidden", "rejected"):
        print(f"  {s:9} {by_status.get(s, 0):>8,}")
    print(f"  {'total':9} {len(rows):>8,}")

    print("\n=== duplicate groups ===")
    print(f"  groups                         {len(groups):>8,}")
    print(f"    linked by Google id          {sum(1 for g in groups if 'gid' in g.via):>8,}")
    print(f"    linked by coordinates+name   {sum(1 for g in groups if 'coord' in g.via):>8,}")
    print(f"  copies to delete               {len(losers):>8,}")
    print(f"    of which pending             {sum(1 for m in losers if m.status == 'pending'):>8,}")
    print(f"    of which live                {sum(1 for m in losers if m.status == 'live'):>8,}")
    print(f"  groups with no live copy (-> live)   {sum(1 for g in groups if g.status_reason == 'merged_restored'):>8,}")
    print(f"  groups with more than one live copy  {sum(1 for g in groups if sum(m.status == 'live' for m in g.members) > 1):>8,}")
    print(f"  groups whose names differ            {report['differing_names']:>8,}")
    print(f"  Google-id conflicts (not merged)     {len(report['gid_conflicts']):>8,}")

    print("\n=== people's content on deleted copies (moved to the kept row) ===")
    print(f"  reviews  {sum(m.reviews for m in losers):>8,}   (same-user conflicts dropped: {sum(_review_conflicts(g, reviewers) for g in groups):,})")
    print(f"  media    {sum(m.media for m in losers):>8,}")
    print(f"  visits   {sum(m.visits for m in losers):>8,}")
    held = sum(favourites.get(m.id, 0) for m in losers)
    print(f"  saved favourites pointing at deleted copies: {held:,} (kept working by aliases)")

    print("\n=== left over after merging ===")
    print(f"  pending rows with no copy (singletons) {len(singles):>8,}")
    by_month = Counter(
        (s.created_at.strftime("%Y-%m") if s.created_at else "unknown") for s in singles
    )
    for month, n in sorted(by_month.items()):
        print(f"    {month}  {n:>7,}")
    print(f"  near-duplicate pairs (<25 m, similar name, different spot; not merged) {near:,}")

    print(f"\n=== {min(samples, len(groups))} sample groups (kept row first) ===")
    step = max(1, len(groups) // max(samples, 1))
    for g in groups[::step][:samples]:
        print(f"  -> {g.status}{' (' + g.status_reason + ')' if g.status_reason else ''} via {'+'.join(sorted(g.via))}")
        for i, m in enumerate(g.members):
            mark = "KEEP" if i == 0 else "del "
            print(f"     {mark} {m.status:8} score {score(m):>2}  {m.name[:60]!r}  {m.id}")
    if singles:
        print("\n=== sample singletons ===")
        step = max(1, len(singles) // 10)
        for s in singles[::step][:10]:
            day = s.created_at.strftime("%Y-%m-%d") if s.created_at else "unknown"
            print(f"     {s.status:8} {day} {s.name[:60]!r}  {s.id}")


async def main(args) -> None:
    from app.core.database import async_session
    from app.services import place_visibility

    os.makedirs(LOG_DIR, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    async with async_session() as session:
        rows, reviewers = await _load(session)
        favourites = await _favourite_ids(session)

    candidates = [r for r in rows if is_candidate(r)]
    groups, report = plan_groups(candidates, exact_names_only=args.exact_names_only)
    if args.limit_groups:
        groups = groups[: args.limit_groups]
    in_group = {m.id for g in groups for m in g.members}
    singles = sorted(
        (r for r in candidates if r.status == "pending" and r.id not in in_group),
        key=lambda r: (r.created_at or datetime.min.replace(tzinfo=timezone.utc), r.id),
    )
    loser_ids = {m.id for g in groups for m in g.losers}
    after = [r for r in candidates if r.id not in loser_ids]
    near = near_duplicates(after)

    _print_report(rows, groups, report, reviewers, favourites, singles, near, args.samples)
    print(f"\n  left alone (admin decisions and app suggestions): {len(rows) - len(candidates):,}")

    plan_path = os.path.join(LOG_DIR, f"plan-{stamp}.jsonl")
    with open(plan_path, "w") as f:
        for g in groups:
            f.write(json.dumps({
                "status": g.status, "reason": g.status_reason, "via": sorted(g.via),
                "keep": _row_json(g.survivor), "delete": [_row_json(m) for m in g.losers],
            }) + "\n")
        for c in report["gid_conflicts"]:
            f.write(json.dumps({"gid_conflict": c}) + "\n")
    print(f"\nPlan written to {plan_path}")

    if not args.apply:
        print("Dry run: nothing changed. Re-run with --apply to merge.")
        return

    log_path = os.path.join(LOG_DIR, f"apply-{stamp}.jsonl")
    done = deleted = failed = 0
    with open(log_path, "w") as log:
        for start in range(0, len(groups), args.batch_size):
            batch = groups[start:start + args.batch_size]
            for attempt in (1, 2):
                try:
                    results = []
                    async with async_session() as session:
                        async with session.begin():
                            await session.execute(text("SET LOCAL lock_timeout = '5s'"))
                            for g in batch:
                                results.append(await _apply_group(session, g))
                    for r in results:
                        if r:
                            log.write(json.dumps(r) + "\n")
                            done += 1
                            deleted += r["deleted"]
                    break
                except Exception as e:
                    print(f"  batch at {start} failed (attempt {attempt}): {e}")
                    if attempt == 2:
                        failed += len(batch)
                        log.write(json.dumps({"failed_batch": start, "error": str(e)}) + "\n")
            print(f"  {min(start + args.batch_size, len(groups)):,}/{len(groups):,} groups")

        if args.singletons != "pending" and singles:
            target = args.singletons
            reason = "legacy_restored" if target == "live" else "legacy_inactive"
            async with async_session() as session:
                async with session.begin():
                    n = (await session.execute(text("""
                        UPDATE attractions
                        SET status = :status, status_reason = :reason,
                            reviewed_at = now(), reviewed_by = :by, updated_at = now()
                        WHERE id = ANY(CAST(:ids AS uuid[]))
                          AND status = 'pending' AND status_reason = 'legacy_inactive'
                    """), {
                        "status": target, "reason": reason, "by": MERGE_SCRIPT,
                        "ids": _uuids(s.id for s in singles),
                    })).rowcount
            log.write(json.dumps({"singletons": target, "updated": n}) + "\n")
            print(f"  singletons -> {target}: {n:,}")

    await place_visibility.bump()
    print(f"\nMerged {done:,} groups, deleted {deleted:,} copies, {failed:,} groups failed.")
    print(f"Log written to {log_path}")


def _parse_args(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--apply", action="store_true", help="write the changes (default: dry run)")
    p.add_argument("--batch-size", type=int, default=200)
    p.add_argument("--samples", type=int, default=20)
    p.add_argument("--limit-groups", type=int, default=0, help="only the first N groups")
    p.add_argument(
        "--singletons", choices=("pending", "live", "hidden"), default="pending",
        help="what to do with pending rows that have no copy (default: leave them)",
    )
    p.add_argument(
        "--exact-names-only", action="store_true",
        help="merge only rows whose names are identical (ignoring case)",
    )
    return p.parse_args(argv)


if __name__ == "__main__":
    asyncio.run(main(_parse_args()))
