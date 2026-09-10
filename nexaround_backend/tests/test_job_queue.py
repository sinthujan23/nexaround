"""The Redis job queue's serialisation and context hand-off.

Odyssey generation is enqueued by the API and run by a separate worker
process. What crosses that boundary is a JSON payload, and the worker must
rebuild from it both the job's arguments and the request context that makes
its telemetry attributable. Nothing here touches Redis or Postgres; the
consumer loop itself is exercised against the live stack, not here.
"""
import uuid

from app.core import job_queue, request_context


def test_payload_round_trips_and_stringifies_uuids():
    itin = uuid.uuid4()
    raw = job_queue.encode(
        "generate_odyssey",
        {"itinerary_id": itin, "days": 3, "budget": 1200.5, "start_date": None},
        ctx={"request_id": None, "user_id": None, "route": "/x"},
    )
    job = job_queue.decode(raw)
    assert job["name"] == "generate_odyssey"
    assert uuid.UUID(job["id"])  # a fresh id per enqueue
    # JSON has no UUID type; the worker rebuilds it (odyssey_jobs.run_job).
    assert job["kwargs"]["itinerary_id"] == str(itin)
    assert job["kwargs"]["days"] == 3
    assert job["kwargs"]["budget"] == 1200.5
    assert job["kwargs"]["start_date"] is None
    assert isinstance(job["enqueued_at"], float)


def test_encode_snapshots_current_request_context_by_default():
    rid, uid = uuid.uuid4(), uuid.uuid4()
    request_context.request_id_var.set(rid)
    request_context.user_id_var.set(uid)
    request_context.route_var.set("/api/v1/itineraries/odyssey/generate")
    request_context.app_version_var.set("1.2.3")
    job = job_queue.decode(job_queue.encode("generate_odyssey", {}))
    assert job["ctx"]["request_id"] == str(rid)
    assert job["ctx"]["user_id"] == str(uid)
    assert job["ctx"]["route"] == "/api/v1/itineraries/odyssey/generate"
    assert job["ctx"]["app_version"] == "1.2.3"


def test_restore_context_rebuilds_vars_from_strings():
    rid, uid = uuid.uuid4(), uuid.uuid4()
    job_queue.restore_context({
        "request_id": str(rid), "user_id": str(uid), "client_ip": "10.0.0.1",
        "app_version": "2.0", "platform": "android", "route": "/r",
    })
    snap = request_context.snapshot()
    assert snap["request_id"] == rid
    assert snap["user_id"] == uid
    assert snap["client_ip"] == "10.0.0.1"
    assert snap["platform"] == "android"
    assert snap["route"] == "/r"


def test_restore_context_tolerates_missing_or_garbage_ids():
    job_queue.restore_context({"request_id": "not-a-uuid", "user_id": ""})
    snap = request_context.snapshot()
    # A job always gets *some* request_id so its telemetry rows still group.
    assert isinstance(snap["request_id"], uuid.UUID)
    assert snap["user_id"] is None


def test_keys_are_namespaced_by_database():
    ns = job_queue._ns()
    assert job_queue.pending_key() == f"jobs:{ns}:pending"
    assert job_queue.processing_key() == f"jobs:{ns}:processing"
    assert job_queue.pending_key() != job_queue.processing_key()
