import asyncio
import httpx

async def test():
    base_url = "https://api.nexaround.com/api/v1"
    
    # 1. Register or login to get a token
    # We will try to register a temporary test user
    email = "test_diagnostic_user_new@example.com"
    password = "TestPassword123!"
    
    token = None
    async with httpx.AsyncClient() as client:
        # Register
        print("Registering temporary user...")
        reg_resp = await client.post(
            f"{base_url}/auth/register",
            json={"email": email, "password": password, "display_name": "Diagnostic User"}
        )
        if reg_resp.status_code in (200, 201):
            print("Successfully registered test user!")
            token = reg_resp.json().get("access_token")
        else:
            # Try to login in case already registered
            print("Registration failed, trying login...")
            login_resp = await client.post(
                f"{base_url}/auth/login",
                data={"username": email, "password": password}
            )
            if login_resp.status_code == 200:
                print("Successfully logged in!")
                token = login_resp.json().get("access_token")
            else:
                print(f"Login failed: {login_resp.status_code} - {login_resp.text}")
                return

        if not token:
            print("Failed to obtain access token.")
            return

        print(f"Bearer Token obtained (length {len(token)})")

        # 2. Call the Gemini proxy endpoint with a simple payload
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "contents": [
                {
                    "parts": [
                        {"text": "Hello, please response with exactly one word: Success"}
                    ]
                }
            ]
        }
        
        print("Calling /proxy/gemini/generate on api.nexaround.com...")
        proxy_resp = await client.post(
            f"{base_url}/proxy/gemini/generate",
            json=payload,
            headers=headers,
            timeout=30.0
        )
        
        print(f"Response Status Code: {proxy_resp.status_code}")
        # Print only safe characters
        clean_text = "".join([c for c in proxy_resp.text if ord(c) < 128])
        print(f"Response Body: {clean_text}")

if __name__ == "__main__":
    asyncio.run(test())
