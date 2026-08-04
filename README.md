# NexAround — AI-Powered Smart Tourism Companion

NexAround is a state-of-the-art, AI-powered smart tourism platform designed to transform how travelers explore and experience the world. It provides real-time augmented reality (AR) exploration, personalized local discovery recommendations, and an intelligent AI companion named Neva.

The platform is structured into three primary subprojects:
1. **`nexaround_app`**: A feature-rich Flutter mobile application.
2. **`nexaround_backend`**: A scalable FastAPI Python backend utilizing geospatial queries and AI capabilities.
3. **`nexaround_admin`**: A modern React + Vite dashboard for administrative management.

---

## 📸 Core Features

*   **🔮 Neva — Your AI Companion**: A witty, warm, and stylish travel partner. Neva answers context-aware queries about history, local delicacies, budgets, and itineraries, complete with beautiful formatting, bullet highlights, and emojis.
*   **🕶 AR Mode & Live Identification**: Uses the device camera and ML Kit Object Detection/Google GenAI to dynamically scan, identify, and label landmarks in real-time AR.
*   **🗺 Living Maps & Travel Planning**: Fully-featured Google Maps & Mapbox navigation pages with custom markers, routing, travel itineraries, and location-based filters.
*   **⚡ Quick Action Integrations**: Directly navigate via internal Google Maps, book stays on Booking.com, or order rides via Uber deep links directly from discovery cards.
*   **🚀 Geospatial Caching Engine**: Custom Postgres + GeoAlchemy2 + Redis caching system that saves API calls and serves location-based results instantly.

---

## 🛠 Tech Stack

### Mobile Client (`nexaround_app`)
*   **Framework**: Flutter & Dart
*   **State Management**: BLoC (`flutter_bloc`)
*   **UI & Animations**: `flutter_animate`, `shimmer`, `lottie`
*   **Location & Mapping**: `google_maps_flutter`, `mapbox_maps_flutter`, `flutter_map`, `geolocator`, `flutter_compass`
*   **On-Device AI & API**: `google_mlkit_object_detection`, `google_generative_ai` (Gemini API)
*   **Utilities**: `get_it` (Dependency Injection), `dio` & `retrofit` (Networking), `hive` & `shared_preferences` (Local storage), `firebase_core` & `firebase_auth`

### Backend Service (`nexaround_backend`)
*   **Framework**: FastAPI, Uvicorn
*   **Database**: PostgreSQL with PostGIS extension (`geoalchemy2`, `shapely`, `asyncpg`)
*   **ORM / Migrations**: SQLAlchemy (Async), Alembic
*   **Caching**: Redis
*   **AI Integration**: `google-genai` (Gemini), `anthropic` (Claude)
*   **Auth & Messaging**: `firebase-admin`, `google-auth`
*   **Computer Vision**: OpenCV (`opencv-python`), Pillow

### Admin Dashboard (`nexaround_admin`)
*   **Framework**: React (v19) + Vite
*   **Routing**: React Router DOM
*   **Linter**: ESLint

---

## 🚀 Getting Started

### 1. Prerequisite Setup
Ensure you have the following installed on your machine:
*   [Flutter SDK](https://docs.flutter.dev/get-started/install)
*   [Python 3.10+](https://www.python.org/downloads/)
*   [Node.js & npm](https://nodejs.org/)
*   [PostgreSQL with PostGIS](https://postgis.net/install/)
*   [Redis](https://redis.io/docs/latest/operate/oss_and_stack/install/)

---

### 2. Backend Installation & Run
1. Navigate to the backend directory:
   ```bash
   cd nexaround_backend
   ```
2. Create and activate a python virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Configure environment variables by copying `.env.example` to `.env` and updating the credentials:
   ```bash
   cp .env.example .env
   ```
5. Apply database migrations:
   ```bash
   alembic upgrade head
   ```
6. Launch the backend server:
   ```bash
   uvicorn app.main:app --reload
   ```

### 2.1 Seeding Museum Data from Excel
Several museums have pre-defined itineraries and masterpieces defined in Excel spreadsheets (located in `nexaround_app/`). To seed them into the database, follow these steps:

#### Method A: Using Docker (Recommended)
1. **Copy the Excel spreadsheet** to the backend `app/` folder so it is visible within the API container volume mount:
   ```bash
   cp nexaround_app/Acropolis_Museum_Itineraries_with_Locations.xlsx nexaround_backend/app/
   ```
2. **Install required dependencies** (`pandas` and `openpyxl`) in the running container if not already installed:
   ```bash
   docker compose exec api pip install pandas openpyxl
   ```
3. **Execute the seed script** using `docker compose exec`, passing the Excel file path via the corresponding environment variable:
   ```bash
   docker compose exec -e ACROPOLIS_XLSX=/app/app/Acropolis_Museum_Itineraries_with_Locations.xlsx api python -m app.scripts.seed_acropolis
   ```

#### Method B: Using Host Python Virtual Environment
1. Ensure the virtual environment is activated and requirements are installed:
   ```bash
   cd nexaround_backend
   source venv/bin/activate
   pip install pandas openpyxl
   ```
2. Run the seed script directly from the backend root directory (the script defaults to finding the spreadsheet in the peer `nexaround_app` directory):
   ```bash
   python -m app.scripts.seed_acropolis
   ```

### 2.2 VPS Docker Deployment Guide
For full VPS deployment instructions, Docker Compose stack configurations, and database seeding procedures, see [VPS_DEPLOYMENT_GUIDE.md](file:///var/www/nexaround/VPS_DEPLOYMENT_GUIDE.md).

---


### 3. Flutter App Installation & Run
1. Navigate to the mobile app directory:
   ```bash
   cd nexaround_app
   ```
2. Fetch Flutter packages:
   ```bash
   flutter pub get
   ```
3. Run the source code generator (for BLoC, Injectable, Retrofit, Freezed):
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```
4. Run the application on your simulator/emulator/connected device:
   ```bash
   flutter run
   ```

---

### 4. Admin Dashboard Installation & Run
1. Navigate to the admin directory:
   ```bash
   cd nexaround_admin
   ```
2. Install Node dependencies:
   ```bash
   npm install
   ```
3. Launch the development server:
   ```bash
   npm run dev
   ```

---

## 📄 License
This project is proprietary and confidential. All rights reserved.
