import asyncio
import sys
import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy import Column, String

Base = declarative_base()

class SystemSetting(Base):
    __tablename__ = 'system_settings'
    key = Column(String, primary_key=True)
    value = Column(String)

async def main():
    if len(sys.argv) < 2:
        print("❌ Usage: python update_and_check_gemini.py <YOUR_GEMINI_API_KEY>")
        return

    new_api_key = sys.argv[1].strip()
    if not new_api_key:
        print("❌ Invalid API Key.")
        return

    # Inside container, we connect to db:5432
    db_url = "postgresql+asyncpg://nexaround:nexaround@db:5432/nexaround"
    try:
        engine = create_async_engine(db_url)
        async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
        async with async_session() as session:
            # Check if exists
            result = await session.execute(
                select(SystemSetting).where(SystemSetting.key == 'gemini_api_key')
            )
            setting = result.scalar_one_or_none()
            
            if setting:
                # Update
                await session.execute(
                    update(SystemSetting)
                    .where(SystemSetting.key == 'gemini_api_key')
                    .values(value=new_api_key)
                )
            else:
                # Insert
                new_setting = SystemSetting(key='gemini_api_key', value=new_api_key)
                session.add(new_setting)
            
            await session.commit()
            print(f"✅ Successfully updated gemini_api_key in DB (length: {len(new_api_key)}, starts with: {new_api_key[:6]})")
    except Exception as e:
        print(f"❌ Failed to connect to database: {e}")
        return

    # Now let's test the Gemini models
    models = [
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "gemini-2.5-pro",
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
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={new_api_key}"
            try:
                resp = await client.post(
                    url,
                    json=payload,
                    headers={"Content-Type": "application/json"},
                    timeout=10.0
                )
                print(f"🤖 Model: {model:22} -> Status Code: {resp.status_code}")
                if resp.status_code == 200:
                    data = resp.json()
                    text = data['candidates'][0]['content']['parts'][0]['text'].strip()
                    print(f"   Response: \"{text}\"")
                else:
                    print(f"   Error Response: {resp.text.strip()[:300]}")
            except Exception as ex:
                print(f"   Exception for {model}: {ex}")

if __name__ == "__main__":
    asyncio.run(main())
