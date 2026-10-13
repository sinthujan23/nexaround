"""Hidden places stay out of what the app is served, cache or not."""
import asyncio
import uuid

from app.services import place_visibility as pv

HID = str(uuid.uuid4())
PEND = str(uuid.uuid4())
REJ_NO_GID = str(uuid.uuid4())


def _rows():
    # (id, google_place_id, status, lat, lng, name, gid_has_live_row)
    return [
        (HID, "ChIJhidden", "hidden", 6.9, 79.85, "Old Fort Cafe", False),
        (PEND, "ChIJpending", "pending", 6.91, 79.86, "Galle Face", True),
        (str(uuid.uuid4()), "ChIJshared", "rejected", 6.92, 79.87, "Shared", True),
        (REJ_NO_GID, None, "rejected", 7.0, 80.0, "Fake Waterfall", False),
    ]


def test_snapshot_contents():
    snap = pv.build_snapshot(_rows())
    # every non-live id
    assert {HID, PEND, REJ_NO_GID} <= snap.ids
    # Google ids only for hidden/rejected without a live twin
    assert snap.gids == {"ChIJhidden"}
    # the rejected row without a Google id goes into the proximity grid
    assert sum(len(v) for v in snap.grid.values()) == 1


def test_is_hidden_by_local_id_and_google_id():
    snap = pv.build_snapshot(_rows())
    assert pv.is_hidden(snap, {"id": HID})
    assert pv.is_hidden(snap, {"id": PEND})
    assert pv.is_hidden(snap, {"id": "ChIJhidden"})
    # pending rows' Google ids belong to live places
    assert not pv.is_hidden(snap, {"id": "ChIJpending"})
    # a Google id that also has a live row stays visible
    assert not pv.is_hidden(snap, {"id": "ChIJshared"})


def test_google_twin_matched_by_distance_and_name():
    snap = pv.build_snapshot(_rows())
    near = {"id": "ChIJother", "latitude": 7.00005, "longitude": 80.00005,
            "name": "fake waterfall viewpoint"}
    far = dict(near, latitude=7.001)
    other_name = dict(near, name="Tea Shop")
    assert pv.is_hidden(snap, near)
    assert not pv.is_hidden(snap, far)
    assert not pv.is_hidden(snap, other_name)


def test_local_rows_skip_the_proximity_match():
    snap = pv.build_snapshot(_rows())
    live_local = {"id": str(uuid.uuid4()), "latitude": 7.0, "longitude": 80.0,
                  "name": "Fake Waterfall"}
    assert not pv.is_hidden(snap, live_local)


def test_filter_keeps_order_and_accepts_models():
    from datetime import datetime, timezone
    from app.schemas.place import PlaceResponse

    snap = pv.build_snapshot(_rows())
    keep = PlaceResponse(id="ChIJok", name="Ok", latitude=1, longitude=1,
                         created_at=datetime.now(timezone.utc))
    drop = PlaceResponse(id=HID, name="Old Fort Cafe", latitude=6.9, longitude=79.85,
                         created_at=datetime.now(timezone.utc))
    assert pv.filter_with(snap, [keep, drop, keep]) == [keep, keep]
    assert pv.filter_with(pv.EMPTY, [drop]) == [drop]


def test_reloads_when_another_process_bumps(monkeypatch):
    loads = []
    version = {"v": "1"}

    async def _load():
        loads.append(1)
        return pv.build_snapshot(_rows())

    async def _read_version():
        return version["v"]

    monkeypatch.setattr(pv, "_load", _load)
    monkeypatch.setattr(pv, "_read_version", _read_version)
    clock = {"t": 1000.0}
    monkeypatch.setattr(pv.time, "monotonic", lambda: clock["t"])

    async def settle():
        if pv._refresh_task is not None:
            await pv._refresh_task

    async def run():
        # first request in a process waits for the first load
        snap = await pv.current()
        assert len(loads) == 1 and HID in snap.ids
        # within the check interval: nothing asked, nothing loaded
        clock["t"] += 1
        await pv.current()
        assert pv._refresh_task is None and len(loads) == 1
        # interval passed, version unchanged: checked, not reloaded
        clock["t"] += 5
        await pv.current()
        await settle()
        assert len(loads) == 1
        # another process bumped: the request is served at once, the reload
        # happens behind it
        version["v"] = "2"
        clock["t"] += 5
        served = await pv.current()
        assert served is snap
        await settle()
        assert len(loads) == 2
        # this process changed a status: its next request starts a reload
        await pv.bump()
        await pv.current()
        await settle()
        assert len(loads) == 3

    asyncio.run(run())


def test_failed_load_fails_open(monkeypatch):
    async def _boom():
        raise RuntimeError("db down")

    monkeypatch.setattr(pv, "_load", _boom)
    assert asyncio.run(pv.current()) is pv.EMPTY
