# 🚀 NexAround VPS Deployment & Operations Guide (Docker Setup)

This guide documents the production deployment, database seeding, and server maintenance workflow for **NexAround Backend** on a VPS server using **Docker Compose**.

---

## ⚡ Quick Deployment Steps (For Server-Side Engineer)

To deploy the latest changes, update database itineraries/opening hours, and restart backend services, run the following **4 steps** directly on your VPS:

```bash
# 1. Pull the latest git changes
git pull origin main

# 2. Navigate to the backend directory
cd nexaround_backend

# 3. Seed Musée d'Orsay itineraries & opening hours into the DB via Docker
docker compose exec api python -m app.scripts.seed_all_museums
docker compose exec api python -m app.scripts.seed_musee_dorsay

# 4. Rebuild container (if code/deps changed) & restart backend service
docker compose up -d --build api
```

*(Note: If code changes do not require rebuilding the image, you can simply run `docker compose restart api`).*

---

## 🏗️ System Architecture Overview

```
                      ┌───────────────────────────────────────────────┐
                      │                   VPS Host                    │
                      │                                               │
                      │               ┌───────────────┐               │
  HTTPS (443) ───────┼──────────────►│ Nginx Reverse │               │
                      │               │     Proxy     │               │
                      │               └───────┬───────┘               │
                      │                       │                       │
                      │                       ▼ (Docker Bridge Network)
                      │             ┌──────────────────┐              │
                      │             │   Compose Pod    │              │
                      │             │                  │              │
                      │             │   ┌──────────┐   │              │
                      │             │   │  api:    │   │              │
                      │             │   │  Port    │   │              │
                      │             │   │  8000    │   │              │
                      │             │   └────┬───┬─┘   │              │
                      │             │        │   │     │              │
                      │             │        ▼   ▼     │              │
                      │             │    ┌───┴─┐ ┌─┴───┐              │
                      │             │    │ db: │ │redis│              │
                      │             │    └─────┘ └─────┘              │
                      │             └──────────────────┘              │
                      └───────────────────────────────────────────────┘
```

The application runs inside a isolated Docker network managed by **Docker Compose**:
* **`api` Container**: FastAPI Python server on port `8000` (mapped to `127.0.0.1:8010` on host).
* **`db` Container**: PostgreSQL 16 with PostGIS 3.4 on port `5432` (internal & host bound).
* **`redis` Container**: Redis 7 cache server listening internally on port `6379`.
* **Nginx Proxy**: Serves SSL via Let's Encrypt certificates (`api.nexaround.com`) and forwards traffic to `127.0.0.1:8000` (or `127.0.0.1:8010`).

---

## ⚙️ Environment & Initial Setup

### 1. Environment File (`nexaround_backend/.env`)
Ensure `.env` exists inside `nexaround_backend/` with production credentials:

```ini
DATABASE_URL=postgresql+asyncpg://nexaround:nexaround@db:5432/nexaround
REDIS_URL=redis://redis:6379/0
GOOGLE_API_KEY=your_google_places_and_gemini_api_key
ANTHROPIC_API_KEY=your_anthropic_api_key
```

### 2. Firebase Service Account Credential
The backend volume-mounts the Firebase service account credential file at:
```bash
/etc/nexaround/firebase-sa.json
```
Ensure this file exists on the host machine with appropriate read permissions.

---

## 🗄️ Full Initial Deployment & Seeding Guide

For new VPS provisioning or initial database hydration:

### Step 1: Start Docker Services
```bash
cd /var/www/nexaround/nexaround_backend
docker compose up -d --build
```

### Step 2: Run Database Migrations
```bash
docker compose exec api alembic upgrade head
```

### Step 3: Seed Database Datasets
Run the seeding scripts inside the active container using `docker compose exec`:

```bash
# Seed Core Categories
docker compose exec api python -m app.scripts.seed_categories

# Seed Top World Museums List & Musée d'Orsay
docker compose exec api python -m app.scripts.seed_all_museums
docker compose exec api python -m app.scripts.seed_musee_dorsay

# Seed Louvre & Vatican Itineraries
docker compose exec api python -m app.scripts.seed_louvre_vatican

# Seed Uffizi & Other Museum Itineraries
docker compose exec api python -m app.scripts.seed_uffizi
docker compose exec api python -m app.scripts.seed_acropolis
```

---

## 🔒 SSL & Nginx Configuration

The VPS uses Nginx on the host to manage SSL certificates via Certbot.

### Initial SSL Setup Script
Run as root/sudo:
```bash
cd /var/www/nexaround/nexaround_backend
sudo bash setup_ssl.sh
```

### Nginx Site Configuration (`/etc/nginx/sites-available/nexaround`)
```nginx
server {
    listen 80;
    server_name api.nexaround.com;

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name api.nexaround.com;

    client_max_body_size 50M;

    ssl_certificate /etc/letsencrypt/live/api.nexaround.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.nexaround.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

---

## 🛠️ Operations & Troubleshooting Commands

### View Live Container Logs
```bash
# Stream API container logs in real time
docker compose logs -f api

# View database container logs
docker compose logs -f db
```

### Check Container Status
```bash
docker compose ps
```

### Restart Backend Services
```bash
# Restart API container only
docker compose restart api

# Restart all stack containers
docker compose restart
```

### Database & Health Diagnostic Check
```bash
docker compose exec api python check_db.py
```
