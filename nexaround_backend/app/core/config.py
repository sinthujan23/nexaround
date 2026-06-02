from typing import List, Union
from pydantic import AnyHttpUrl, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    PROJECT_NAME: str = "NexAround"
    API_V1_STR: str = "/api/v1"
    
    # CORS
    BACKEND_CORS_ORIGINS: List[AnyHttpUrl] = []

    @field_validator("BACKEND_CORS_ORIGINS", mode="before")
    @classmethod
    def assemble_cors_origins(cls, v: Union[str, List[str]]) -> Union[List[str], str]:
        if isinstance(v, str) and not v.startswith("["):
            return [i.strip() for i in v.split(",")]
        elif isinstance(v, (list, str)):
            return v
        raise ValueError(v)

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://nexaround:nexaround@localhost:5432/nexaround"
    
    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"
    
    # AI Keys
    ANTHROPIC_API_KEY: str = ""
    GOOGLE_API_KEY: str = ""
    HUGGINGFACE_API_KEY: str = ""

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
