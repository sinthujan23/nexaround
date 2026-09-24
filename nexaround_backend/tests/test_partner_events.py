"""The partner portal's live-updates stream.

Nothing here needs Redis or a database: the stream takes its Redis client and
its session check as arguments, so a fake of each drives every exit path.
"""
import asyncio
import json
import time

from app.core.database import get_db
from app.services import partner_events


class FakePubSub:
    def __init__(self, messages=()):
        self.messages = list(messages)
        self.channels = []
        self.closed = False

    async def subscribe(self, name):
        self.channels.append(name)

    async def get_message(self, ignore_subscribe_messages, timeout):
        return self.messages.pop(0) if self.messages else None

    async def aclose(self):
        self.closed = True


class FakeRedis:
    def __init__(self, pubsub=None):
        self._pubsub = pubsub or FakePubSub()
        self.published = []

    def pubsub(self):
        return self._pubsub

    async def publish(self, name, payload):
        self.published.append((name, payload))


def _event(event_type, data=None):
    return {"type": "message", "data": json.dumps({"type": event_type, "data": data or {}})}


def _collect(redis, *, limit=10, expires_in=3600, problem=None):
    async def session_problem():
        if isinstance(problem, Exception):
            raise problem
        return problem

    async def run():
        frames = []
        gen = partner_events.stream(
            redis, "v-1",
            expires_at=time.time() + expires_in,
            session_problem=session_problem,
        )
        try:
            async for frame in gen:
                frames.append(frame)
                if len(frames) >= limit:
                    break
        finally:
            await gen.aclose()
        return frames

    return asyncio.run(run())


def _names(frames):
    return [
        f.split("\n", 1)[0].removeprefix("event: ") if f.startswith("event:") else "ping"
        for f in frames
    ]


def test_sse_frame_keeps_the_payload_on_one_data_line():
    frame = partner_events.sse("enquiry.created", {"message": "two\nlines"})
    assert frame.endswith("\n\n")
    lines = frame[:-2].split("\n")
    assert lines[0] == "event: enquiry.created"
    assert len(lines) == 2 and lines[1].startswith("data: ")
    assert json.loads(lines[1][len("data: "):]) == {"message": "two\nlines"}


def test_stream_subscribes_to_its_own_vendor_only():
    redis = FakeRedis()
    _collect(redis, limit=1)
    assert redis.pubsub().channels == [partner_events.channel("v-1")]


def test_stream_opens_with_ready_then_heartbeats_when_idle():
    frames = _collect(FakeRedis(), limit=3)
    assert _names(frames) == ["ready", "ping", "ping"]
    assert frames[1] == ": ping\n\n"


def test_event_is_forwarded_after_the_session_check_passes():
    redis = FakeRedis(FakePubSub([_event("enquiry.created", {"id": "e-1"})]))
    frames = _collect(redis, limit=2)
    assert _names(frames) == ["ready", "enquiry.created"]
    assert '"id": "e-1"' in frames[1]


def test_a_dead_session_ends_the_stream_before_the_event_is_sent():
    """The event carries a traveller's name; a suspended vendor must not get it."""
    redis = FakeRedis(FakePubSub([_event("enquiry.created", {"contact_name": "Jane"})]))
    frames = _collect(redis, problem="Your listing is currently suspended.")
    assert _names(frames) == ["ready", "session.ended"]
    assert "suspended" in frames[1]
    assert not any("Jane" in f for f in frames)


def test_an_expired_token_ends_the_stream():
    frames = _collect(FakeRedis(), expires_in=-1)
    assert _names(frames) == ["ready", "session.ended"]
    assert partner_events.SESSION_EXPIRED_MESSAGE in frames[1]


def test_a_failing_session_check_closes_without_signing_out():
    """A database blip must not sign every vendor out; the portal reconnects."""
    redis = FakeRedis(FakePubSub([_event("enquiry.created")]))
    frames = _collect(redis, problem=RuntimeError("db down"))
    assert _names(frames) == ["ready"]


def test_malformed_messages_are_dropped_not_fatal():
    redis = FakeRedis(FakePubSub([
        {"type": "message", "data": "not json"},
        _event("packages.changed"),
    ]))
    frames = _collect(redis, limit=2)
    assert _names(frames) == ["ready", "packages.changed"]


def test_subscription_is_closed_when_the_tab_goes_away():
    redis = FakeRedis()
    _collect(redis, limit=2)
    assert redis.pubsub().closed


def test_publish_goes_to_the_vendor_channel(monkeypatch):
    redis = FakeRedis()

    async def fake_client():
        return redis

    monkeypatch.setattr(partner_events, "get_redis_client", fake_client)
    asyncio.run(partner_events.publish("v-9", "enquiry.updated", {"id": 1}))
    assert redis.published == [
        (partner_events.channel("v-9"), json.dumps({"type": "enquiry.updated", "data": {"id": 1}}))
    ]


def test_publish_never_raises(monkeypatch):
    """The enquiry is already committed; Redis being down must not 500 it."""
    async def broken_client():
        raise ConnectionError("redis down")

    monkeypatch.setattr(partner_events, "get_redis_client", broken_client)
    asyncio.run(partner_events.publish("v-1", "enquiry.created", {}))
    asyncio.run(partner_events.publish(None, "enquiry.created", {}))


def test_events_route_never_holds_a_db_session():
    """FastAPI closes yield-dependencies after the response is sent, so a
    `get_db` anywhere in this route's tree would pin a pool connection for as
    long as a portal tab stays open."""
    from app.api.v1.partner import router

    route = next(r for r in router.routes if r.path == "/partner/events")

    def calls(dependant):
        yield dependant.call
        for sub in dependant.dependencies:
            yield from calls(sub)

    assert get_db not in set(calls(route.dependant))
