from fastapi import APIRouter
from app.api.v1.auth import router as auth_router
from app.api.v1.attractions import router as attractions_router
from app.api.v1.categories import router as categories_router
from app.api.v1.chat import router as chat_router
from app.api.v1.itineraries import router as itineraries_router
from app.api.v1.reviews import router as reviews_router
from app.api.v1.ar import router as ar_router

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth_router)
api_router.include_router(attractions_router)
api_router.include_router(categories_router)
api_router.include_router(chat_router)
api_router.include_router(itineraries_router)
api_router.include_router(reviews_router)
api_router.include_router(ar_router, prefix="/ar", tags=["AR"])
