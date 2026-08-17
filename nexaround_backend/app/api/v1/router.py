from fastapi import APIRouter
from app.api.v1.auth import router as auth_router
from app.api.v1.attractions import router as attractions_router
from app.api.v1.categories import router as categories_router
from app.api.v1.chat import router as chat_router
from app.api.v1.itineraries import router as itineraries_router
from app.api.v1.reviews import router as reviews_router
from app.api.v1.ar import router as ar_router
from app.api.v1.budget import router as budget_router
from app.api.v1.places import router as places_router
from app.api.v1.admin import router as admin_router
from app.api.v1.telemetry_admin import router as telemetry_admin_router
from app.api.v1.proxy import router as proxy_router
from app.api.v1.notifications import router as notifications_router
from app.api.v1.travel_stories import router as travel_stories_router
from app.api.v1.discovery import router as discovery_router
from app.api.v1.museums import router as museums_router

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth_router)
api_router.include_router(attractions_router)
api_router.include_router(categories_router)
api_router.include_router(chat_router)
api_router.include_router(itineraries_router)
api_router.include_router(reviews_router)
api_router.include_router(budget_router)
api_router.include_router(places_router)
api_router.include_router(admin_router)
api_router.include_router(telemetry_admin_router)
api_router.include_router(proxy_router)
api_router.include_router(notifications_router)
api_router.include_router(travel_stories_router)
api_router.include_router(discovery_router)
api_router.include_router(museums_router)
api_router.include_router(ar_router, prefix="/ar", tags=["AR"])

