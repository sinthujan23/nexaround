import json
from typing import List, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "NexAround"
    API_V1_STR: str = "/api/v1"
    ENABLE_DOCS: bool = False
    
    # JWT Security Configuration
    SECRET_KEY: str = ""
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60  # 1 hour
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Admin Portal Credentials
    ADMIN_USERNAME: str = "admin"
    ADMIN_PASSWORD: str = ""

    @field_validator("ADMIN_PASSWORD", mode="before")
    @classmethod
    def validate_admin_password(cls, v: Union[str, None]) -> str:
        if not v or v == "password123":
            import secrets
            import logging
            logging.warning("ADMIN_PASSWORD not set or insecure default used. Generating dynamic admin password.")
            return secrets.token_hex(32)
        return v

    @field_validator("SECRET_KEY", mode="before")
    @classmethod
    def validate_secret_key(cls, v: Union[str, None]) -> str:
        if not v or v == "nexaround-super-secret-key-change-in-production":
            import secrets
            import logging
            logging.warning("SECRET_KEY not found or insecure default used. Generating ephemeral secret key.")
            return secrets.token_hex(32)
        return v

    # CORS
    BACKEND_CORS_ORIGINS: Union[List[str], str] = []

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            if not v:
                return []
            if v.startswith("[") and v.endswith("]"):
                import json
                try:
                    return [str(i).strip().rstrip("/") for i in json.loads(v) if str(i).strip()]
                except Exception:
                    pass
            return [i.strip().rstrip("/") for i in v.split(",") if i.strip()]
        elif isinstance(v, list):
            return [str(i).strip().rstrip("/") for i in v if str(i).strip()]
        return []

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://nexaround_app:placeholder@localhost:5432/nexaround_prod"
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    
    # AI Keys
    ANTHROPIC_API_KEY: str = ""
    GOOGLE_API_KEY: str = ""
    HUGGINGFACE_API_KEY: str = ""

    # OAuth Client IDs for token verification
    GOOGLE_CLIENT_IDS: Union[List[str], str] = [
        # nexaround-e9a5e / com.nexaround.app
        "375268962043-vb9adud6hglf3jd1vme6dku0dshdch38.apps.googleusercontent.com",  # iOS
        "375268962043-4j3q1v1qcl5feif820ebib08l48b0s6n.apps.googleusercontent.com",  # Android
        "375268962043-dsvvrgcdc9l38dnfkkveb2f51qcf6o43.apps.googleusercontent.com",  # Web (serverClientId -> token aud)
        "375268962043",
        "501648798743-s475las96nn5m01l105dikmm74ghuhf9.apps.googleusercontent.com",
        "501648798743-fpj6ua4dqdgov8hffm7504aekvjne4kh.apps.googleusercontent.com",
        "501648798743-vjrfvouhnk2o0p6qm7ob595hfm68th48.apps.googleusercontent.com",
        "501648798743-fghkh72pqh34u787m2aq2hn8dmnmcuiq.apps.googleusercontent.com",
        "501648798743-kqev2d391necv2mvlqeoitmch9i05rv5.apps.googleusercontent.com",
        "501648798743-0omovnor0thg338btth5n0b7r0oq1r9h.apps.googleusercontent.com",
    ]
    APPLE_CLIENT_IDS: Union[List[str], str] = [
        "com.nexaround.app",
        "com.nexaround.app.service",
        "com.nexaround.nexaround_app.service",
        "com.nexaround.nexaroundApp.5X9A8V7S49",
        "com.nexaround.nexaround_app",
        "com.nexaround.nexaroundApp",
    ]

    # SMTP Email Settings for OTP Verification
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USER: str = ""
    SMTP_PASSWORD: str = ""
    EMAILS_FROM_EMAIL: str = "noreply@nexaround.com"

    @field_validator("GOOGLE_CLIENT_IDS", "APPLE_CLIENT_IDS", mode="before")
    @classmethod
    def assemble_client_ids(cls, v: Union[str, List[str]]) -> List[str]:
        if isinstance(v, str):
            v = v.strip()
            if not v:
                return []
            if v.startswith("["):
                # A JSON array in .env. Parsing it (rather than falling through
                # to an empty list) matters: an empty list disables OAuth
                # audience validation entirely.
                try:
                    v = json.loads(v)
                except json.JSONDecodeError as e:
                    raise ValueError(f"Invalid JSON list for client IDs: {e}") from e
            else:
                return [i.strip() for i in v.split(",") if i.strip()]
        if isinstance(v, list):
            return [str(i).strip() for i in v if str(i).strip()]
        raise ValueError(f"Unsupported client ID value of type {type(v).__name__}")


    # Firebase push notifications. Provide ONE of these (via .env / server env,
    # NOT committed to git). Most secure first:
    #   FIREBASE_SERVICE_ACCOUNT_FILE — absolute path to the service-account
    #       .json on the server (e.g. /etc/nexaround/firebase-sa.json)
    #   FIREBASE_SERVICE_ACCOUNT_JSON — the raw JSON, or its base64, inline
    # If neither is set, the backend falls back to the admin-panel DB setting.
    FIREBASE_SERVICE_ACCOUNT_FILE: str = ""
    FIREBASE_SERVICE_ACCOUNT_JSON: str = ""

    model_config = SettingsConfigDict(
        case_sensitive=True, 
        env_file=".env",
        extra="ignore"
    )

settings = Settings()
