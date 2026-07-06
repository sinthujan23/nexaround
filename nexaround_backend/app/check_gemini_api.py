import asyncio
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy import Column, String
import httpx

Base = declarative_base()

class SystemSetting(Base):
    __tablename__ = 'system_settings'
    key = Column(String, primary_key=True)
    value = Column(String)

async def check():
    # Inside container, we connect to db:5432
    db_url = "postgresql+asyncpg://nexaround:nexaround@db:5432/nexaround"
    try:
        engine = create_async_engine(db_url)
        async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
        async with async_session() as session:
            result = await session.execute(
                select(SystemSetting).where(SystemSetting.key == 'gemini_api_key')
            )
            setting = result.scalar_one_or_none()
            if not setting or not setting.value:
                print("gemini_api_key not found in system_settings table.")
                return
            api_key = setting.value
            print(f"Found gemini_api_key in DB (length: {len(api_key)}, starts with: {api_key[:6]})")
    except Exception as e:
        print(f"Failed to connect to container database: {e}")
        return

    # Now let's test the Gemini models
    models = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "gemini-flash-latest"
    ]

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": "Hello, write a 3 word greeting."}
                ]
            }
        ]
    }

    async with httpx.AsyncClient() as client:
        for model in models:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            try:
                resp = await client.post(
                    url,
                    json=payload,
                    headers={"Content-Type": "application/json"},
                    timeout=10.0
                )
                print(f"Model: {model:22} -> Status Code: {resp.status_code}")
                if resp.status_code == 200:
                    data = resp.json()
                    text = data['candidates'][0]['content']['parts'][0]['text'].strip()
                    print(f"   Response: \"{text}\"")
                else:
                    # Strip response to safe characters only
                    clean_err = "".join([c for c in resp.text if ord(c) < 128])
                    print(f"   Error Response: {clean_err[:200]}")
            except Exception as ex:
                print(f"   Exception for {model}: {ex}")

if __name__ == "__main__":
    asyncio.run(check())
