import asyncio
import asyncpg
import httpx
import os
from urllib.parse import quote

DATABASE_URL = "postgresql://nexaround:nexaround@localhost:5432/nexaround"

async def fetch_museum_photos():
    print("Connecting to database...")
    conn = await asyncpg.connect(DATABASE_URL)
    
    # Get Google Maps API Key
    print("Fetching Google Maps API Key...")
    row = await conn.fetchrow("SELECT value FROM system_settings WHERE key = 'google_maps_api_key'")
    if not row or not row['value']:
        print("Error: google_maps_api_key not found in system_settings.")
        await conn.close()
        return
        
    api_key = row['value']
    
    # Get museums without image_url
    museums = await conn.fetch("SELECT id, name, city FROM museums WHERE image_url IS NULL")
    if not museums:
        print("No museums need updating. All have image_url.")
        await conn.close()
        return
        
    print(f"Found {len(museums)} museums to update.")
    
    async with httpx.AsyncClient() as client:
        for museum in museums:
            museum_id = museum['id']
            name = museum['name']
            city = museum['city']
            
            search_query = f"{name} {city}"
            print(f"Searching for: {search_query}")
            
            url = f"https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input={quote(search_query)}&inputtype=textquery&fields=photos&key={api_key}"
            
            try:
                resp = await client.get(url, timeout=10.0)
                resp.raise_for_status()
                data = resp.json()
                
                candidates = data.get("candidates", [])
                if candidates and candidates[0].get("photos"):
                    photos = candidates[0]["photos"]
                    if photos:
                        photo_reference = photos[0]["photo_reference"]
                        # Store the proxy URL
                        proxy_url = f"/api/v1/proxy/google-maps/place/photo?maxwidth=800&photo_reference={photo_reference}"
                        
                        await conn.execute("UPDATE museums SET image_url = $1 WHERE id = $2", proxy_url, museum_id)
                        print(f"  -> Updated with proxy URL")
                    else:
                        print(f"  -> No photos array in candidate")
                else:
                    print(f"  -> No photos found for this place")
            except Exception as e:
                print(f"  -> Error fetching data: {e}")
                
            # Sleep slightly to avoid hitting rate limits too hard
            await asyncio.sleep(0.5)

    await conn.close()
    print("Done!")

if __name__ == "__main__":
    asyncio.run(fetch_museum_photos())
