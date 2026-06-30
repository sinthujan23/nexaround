import asyncio
import sys
import redis.asyncio as aioredis
from app.core.config import settings

async def main():
    print(f"Connecting to Redis at {settings.REDIS_URL}...")
    try:
        r = aioredis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
        )
        
        # We can flush everything
        await r.flushdb()
        print("✅ Redis cache successfully flushed!")
        
    except Exception as e:
        print(f"❌ Failed to flush Redis cache: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
