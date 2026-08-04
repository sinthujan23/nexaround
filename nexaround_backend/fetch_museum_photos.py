import asyncio
import asyncpg
import httpx
import os
from urllib.parse import quote

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://nexaround:nexaround@db:5432/nexaround").replace("postgresql+asyncpg://", "postgresql://")

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
    
    # Get museums without new photo format
    museums = await conn.fetch("SELECT id, name, city FROM museums WHERE image_url IS NULL OR image_url NOT LIKE '%ref=places/%'")
    if not museums:
        print("No museums need updating. All have new image_url format.")
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
            
            url = "https://places.googleapis.com/v1/places:searchText"
            headers = {
                "Content-Type": "application/json",
                "X-Goog-Api-Key": api_key,
                "X-Goog-FieldMask": "places.photos"
            }
            body = {
                "textQuery": search_query
            }
            
            try:
                resp = await client.post(url, json=body, headers=headers, timeout=10.0)
                resp.raise_for_status()
                data = resp.json()
                
                places = data.get("places", [])
                if places and places[0].get("photos"):
                    photos = places[0]["photos"]
                    if photos:
                        photo_reference = photos[0]["name"]
                        # Store the public proxy URL using places/ photo reference
                        proxy_url = f"/api/v1/places/photo?ref={photo_reference}"
                        
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
