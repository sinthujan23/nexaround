import uuid
from typing import Optional
from fastapi import APIRouter, Depends, Request, Form, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.services.attraction_service import AttractionService
from app.services.category_service import CategoryService
from app.schemas.attraction import AttractionCreate

router = APIRouter(prefix="/admin", tags=["admin"])
templates = Jinja2Templates(directory="app/templates")

# Fixed Admin Credentials
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "password123"

@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request, error: Optional[str] = None):
    return templates.TemplateResponse("login.html", {"request": request, "error": error})

@router.post("/login")
async def login(
    request: Request,
    username: str = Form(...),
    password: str = Form(...)
):
    if username == ADMIN_USERNAME and password == ADMIN_PASSWORD:
        response = RedirectResponse(url="/admin/dashboard", status_code=status.HTTP_303_SEE_OTHER)
        # Set a simple cookie for "session"
        response.set_cookie(key="admin_token", value="mission_control_access_granted", httponly=True)
        return response
    
    return templates.TemplateResponse("login.html", {
        "request": request, 
        "error": "Access Denied: Invalid commander credentials."
    })

@router.get("/logout")
async def logout():
    response = RedirectResponse(url="/admin/login", status_code=status.HTTP_303_SEE_OTHER)
    response.delete_cookie("admin_token")
    return response

# Dependency to protect routes
async def check_admin_auth(request: Request):
    token = request.cookies.get("admin_token")
    if token != "mission_control_access_granted":
        raise HTTPException(
            status_code=status.HTTP_307_TEMPORARY_REDIRECT,
            headers={"Location": "/admin/login"}
        )
    return token

@router.get("/", response_class=HTMLResponse)
@router.get("/dashboard", response_class=HTMLResponse)
async def dashboard(
    request: Request, 
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    attraction_service = AttractionService(db)
    attractions_data = await attraction_service.list_attractions(page_size=5)
    
    return templates.TemplateResponse("dashboard.html", {
        "request": request,
        "active_page": "dashboard",
        "recent_attractions": attractions_data.attractions,
        "total_attractions": attractions_data.total
    })

@router.get("/attractions", response_class=HTMLResponse)
async def list_attractions(
    request: Request, 
    page: int = 1, 
    search: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    attraction_service = AttractionService(db)
    category_service = CategoryService(db)
    
    data = await attraction_service.list_attractions(page=page, search_query=search)
    categories = await category_service.get_categories()
    
    return templates.TemplateResponse("attractions/index.html", {
        "request": request,
        "active_page": "attractions",
        "attractions": data.attractions,
        "categories": categories,
        "total": data.total,
        "page": page
    })

@router.get("/attractions/create", response_class=HTMLResponse)
async def create_attraction_page(
    request: Request, 
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    category_service = CategoryService(db)
    categories = await category_service.get_categories()
    
    return templates.TemplateResponse("attractions/edit.html", {
        "request": request,
        "active_page": "attractions",
        "attraction": None,
        "categories": categories
    })

@router.post("/attractions/create")
async def create_attraction(
    request: Request,
    name: str = Form(...),
    description: str = Form(None),
    history: str = Form(None),
    latitude: float = Form(...),
    longitude: float = Form(...),
    address: str = Form(None),
    category_id: str = Form(None),
    entry_fee: float = Form(0.0),
    currency: str = Form("USD"),
    geofence_radius_m: int = Form(100),
    tags: str = Form(""),
    is_active: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    attraction_service = AttractionService(db)
    tag_list = [t.strip() for t in tags.split(",") if t.strip()]
    cat_id = uuid.UUID(category_id) if category_id and category_id != "None" else None
    
    data = AttractionCreate(
        name=name, description=description, history=history,
        latitude=latitude, longitude=longitude, address=address,
        category_id=cat_id, entry_fee=entry_fee, currency=currency,
        geofence_radius_m=geofence_radius_m, tags=tag_list
    )
    
    await attraction_service.create_attraction(data)
    return RedirectResponse(url="/admin/attractions", status_code=status.HTTP_303_SEE_OTHER)

@router.get("/attractions/edit/{attraction_id}", response_class=HTMLResponse)
async def edit_attraction_page(
    request: Request, 
    attraction_id: uuid.UUID, 
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    attraction_service = AttractionService(db)
    category_service = CategoryService(db)
    attraction = await attraction_service.get_attraction(attraction_id)
    categories = await category_service.get_categories()
    
    return templates.TemplateResponse("attractions/edit.html", {
        "request": request, "active_page": "attractions",
        "attraction": attraction, "categories": categories
    })

@router.post("/attractions/edit/{attraction_id}")
async def update_attraction(
    attraction_id: uuid.UUID,
    name: str = Form(...),
    description: str = Form(None),
    history: str = Form(None),
    latitude: float = Form(...),
    longitude: float = Form(...),
    address: str = Form(None),
    category_id: str = Form(None),
    entry_fee: float = Form(0.0),
    currency: str = Form("USD"),
    geofence_radius_m: int = Form(100),
    tags: str = Form(""),
    is_active: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    attraction_service = AttractionService(db)
    tag_list = [t.strip() for t in tags.split(",") if t.strip()]
    cat_id = uuid.UUID(category_id) if category_id and category_id != "None" else None
    
    data = {
        "name": name, "description": description, "history": history,
        "latitude": latitude, "longitude": longitude, "address": address,
        "category_id": cat_id, "entry_fee": entry_fee, "currency": currency,
        "geofence_radius_m": geofence_radius_m, "tags": tag_list,
        "is_active": is_active == "on"
    }
    
    await attraction_service.update_attraction(attraction_id, data)
    return RedirectResponse(url="/admin/attractions", status_code=status.HTTP_303_SEE_OTHER)

@router.get("/categories", response_class=HTMLResponse)
async def list_categories(
    request: Request, 
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    category_service = CategoryService(db)
    categories = await category_service.get_categories()
    return templates.TemplateResponse("categories/index.html", {
        "request": request, "active_page": "categories", "categories": categories
    })

@router.get("/media", response_class=HTMLResponse)
async def media_library(request: Request, _ = Depends(check_admin_auth)):
    return templates.TemplateResponse("media/index.html", {"request": request, "active_page": "media"})

@router.get("/users", response_class=HTMLResponse)
async def user_directory(request: Request, _ = Depends(check_admin_auth)):
    return templates.TemplateResponse("users/index.html", {"request": request, "active_page": "users"})

@router.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request, _ = Depends(check_admin_auth)):
    return templates.TemplateResponse("settings/index.html", {"request": request, "active_page": "settings"})

@router.delete("/attractions/delete/{attraction_id}")
async def delete_attraction(
    attraction_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    _ = Depends(check_admin_auth)
):
    attraction_service = AttractionService(db)
    await attraction_service.delete_attraction(attraction_id)
    return {"status": "success"}
