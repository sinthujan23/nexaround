"""Real engagement metrics for the admin dashboard — computed from tracked
activity (user_sessions, place_visits), never hard-coded."""
from datetime import datetime, timezone, timedelta

from sqlalchemy import select, func

from app.models.analytics import UserSession, PlaceVisit


def _fmt_duration(seconds: float) -> str:
    s = int(round(seconds or 0))
    m, sec = divmod(s, 60)
    return f"{m}m {sec:02d}s" if m else f"{sec}s"


async def get_engagement_stats(db) -> dict:
    now = datetime.now(timezone.utc)
    day_ago = now - timedelta(hours=24)
    week_ago = now - timedelta(days=7)
    month_ago = now - timedelta(days=30)

    # Daily Active Users — distinct users with a session in the last 24h.
    dau = await db.scalar(
        select(func.count(func.distinct(UserSession.user_id))).where(
            UserSession.created_at >= day_ago,
            UserSession.user_id.isnot(None),
        )
    ) or 0

    # Average session length over the last 7 days.
    avg_secs = await db.scalar(
        select(func.avg(UserSession.duration_seconds)).where(
            UserSession.created_at >= week_ago
        )
    ) or 0

    # Places visited in the last 30 days.
    places_visited = await db.scalar(
        select(func.count(PlaceVisit.id)).where(PlaceVisit.created_at >= month_ago)
    ) or 0

    return {
        "daily_active_users": int(dau),
        "avg_session_length": _fmt_duration(float(avg_secs)),
        "places_visited_count": int(places_visited),
    }
