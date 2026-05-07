import logging
import traceback
import re
import json
import httpx
from urllib.parse import urljoin
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)


class GoogleLensService:
    """Google Lens identification service with direct image upload."""

    def __init__(self):
        self._client = httpx.Client(
            timeout=35.0,
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Accept-Encoding": "gzip, deflate, br",
            }
        )
        logger.info("[OK] Google Lens Service initialized")

    def identify(self, image_bytes: bytes) -> dict:
        """
        Upload image to Google Lens and extract AI Overview.
        Uses direct file upload (not base64 in URL).
        """
        try:
            logger.info(f"[LENS] Processing image ({len(image_bytes)} bytes)...")
            
            # Create multipart form data with the image file
            files = {
                'encoded_image': ('image.jpg', image_bytes, 'image/jpeg')
            }
            
            # Upload to Google Lens
            response = self._client.post(
                'https://lens.google.com/v3/upload',
                files=files,
                params={'hl': 'en'},
            )
            
            logger.info(f"   Upload status: {response.status_code}")
            
            if response.status_code == 200:
                # Get the final URL after any redirects
                final_url = str(response.url)
                logger.info(f"   Final URL: {final_url}")
                
                html = response.text
                
                # Try to extract AI Overview from the response
                ai_overview = self._extract_ai_overview(html)
                
                if ai_overview:
                    logger.info(f"[OK] AI Overview extracted")
                    return {
                        "success": True,
                        "ai_overview": ai_overview,
                        "object_name": self._extract_subject(ai_overview),
                        "source": "Google Lens"
                    }
                
                # If we got a redirect URL, follow it
                if 'google.com' in final_url or 'lens.google.com' in final_url:
                    logger.info("   Following to results page...")
                    results_response = self._client.get(final_url)
                    ai_overview = self._extract_ai_overview(results_response.text)
                    
                    if ai_overview:
                        logger.info(f"[OK] AI Overview extracted from results page")
                        return {
                            "success": True,
                            "ai_overview": ai_overview,
                            "object_name": self._extract_subject(ai_overview),
                            "source": "Google Lens"
                        }
            
            # Try direct search by image upload (alternative endpoint)
            return self._search_by_image(image_bytes)
            
        except Exception as e:
            logger.error(f"Google Lens Error: {e}")
            traceback.print_exc()
            return self._error_response(str(e))
    
    def _search_by_image(self, image_bytes: bytes) -> dict:
        """Alternative: Use Google's search by image endpoint."""
        try:
            logger.info("   Trying search by image endpoint...")
            
            files = {
                'encoded_image': ('image.jpg', image_bytes, 'image/jpeg')
            }
            
            response = self._client.post(
                'https://www.google.com/searchbyimage/upload',
                files=files,
                params={'hl': 'en'},
            )
            
            logger.info(f"   Search by image status: {response.status_code}")
            
            if response.status_code == 200:
                html = response.text
                ai_overview = self._extract_ai_overview(html)
                
                if ai_overview:
                    return {
                        "success": True,
                        "ai_overview": ai_overview,
                        "object_name": self._extract_subject(ai_overview),
                        "source": "Google Search by Image"
                    }
            
            return self._error_response("No AI Overview found")
            
        except Exception as e:
            logger.error(f"Search by image failed: {e}")
            return self._error_response(str(e))
    
    def _extract_ai_overview(self, html: str) -> str | None:
        """Extract AI Overview text from Google response."""
        try:
            # Save for debugging (uncomment if needed)
            # with open("debug_response.html", "w", encoding="utf-8") as f:
            #     f.write(html[:50000])
            
            # Look for AI Overview in various formats
            patterns = [
                # Pattern 1: Direct AI Overview text
                r'AI Overview\s*[\n\r]+([^<]{50,800})',
                r'<div[^>]*class="[^"]*overview[^"]*"[^>]*>([^<]{50,800})</div>',
                r'<div[^>]*aria-label="[^"]*Overview[^"]*"[^>]*>([^<]{50,800})</div>',
                
                # Pattern 2: "This image shows" pattern
                r'([Tt]his image shows[^.!?]+[.!?]\s*[^.!?]{0,150}[.!?])',
                r'([Tt]he (?:photo|image|picture) (?:shows|features|displays)[^.!?]+[.!?]\s*[^.!?]{0,150}[.!?])',
                r'([Bb]ased on the image,[^.!?]+[.!?]\s*[^.!?]{0,150}[.!?])',
                
                # Pattern 3: Meta description
                r'<meta[^>]*name="description"[^>]*content="([^"]{50,500})"',
                r'<meta[^>]*property="og:description"[^>]*content="([^"]{50,500})"',
                
                # Pattern 4: Knowledge panel text
                r'<div[^>]*data-attrid="[^"]*description[^"]*"[^>]*>([^<]{50,500})</div>',
                r'<div[^>]*class="[^"]*kno-rdesc[^"]*"[^>]*>.*?<span[^>]*>([^<]{50,500})</span>',
                
                # Pattern 5: JSON embedded data
                r'"snippet":"([^"]{50,500})"',
                r'"description":"([^"]{50,500})"',
                r'"text":"([^"]{50,500})"',
            ]
            
            for pattern in patterns:
                matches = re.findall(pattern, html, re.IGNORECASE | re.DOTALL)
                for match in matches:
                    # Clean the text
                    clean_text = self._clean_text(match)
                    
                    # Validate it's real content
                    if clean_text and 40 < len(clean_text) < 2000:
                        # Filter out junk
                        junk_keywords = ['google', 'lens', 'cookie', 'privacy', 'sign in', 
                                       'javascript', 'base64', 'neva', 'narrating', 'rt', 'rb']
                        if not any(junk in clean_text.lower() for junk in junk_keywords):
                            logger.info(f"   Found valid AI Overview ({len(clean_text)} chars)")
                            return clean_text
            
            # Parse with BeautifulSoup as fallback
            soup = BeautifulSoup(html, 'html.parser')
            
            # Look for specific classes
            selectors = [
                '.VwiC3b', '.yDYNvb', '.kno-fb-ctx', '.iXO9Tb',
                '[data-attrid="kc:/collection/knowledge_panel"]',
                '.kno-rdesc', '.SPZz6b', '.qrShPb'
            ]
            
            for selector in selectors:
                elements = soup.select(selector)
                for element in elements:
                    text = self._clean_text(element.get_text())
                    if text and 40 < len(text) < 2000:
                        if not any(junk in text.lower() for junk in ['google', 'lens', 'cookie']):
                            return text
            
            return None
            
        except Exception as e:
            logger.error(f"Extraction error: {e}")
            return None
    
    def _clean_text(self, text: str) -> str:
        """Clean and normalize text."""
        if not text:
            return ""
        
        # Remove escape sequences
        text = text.replace('\\n', ' ').replace('\\r', ' ').replace('\\t', ' ')
        text = text.replace('\\"', '"').replace("\\'", "'")
        text = text.replace('\\/', '/')
        
        # Remove HTML tags
        text = re.sub(r'<[^>]+>', ' ', text)
        
        # Remove HTML entities
        text = text.replace('&nbsp;', ' ').replace('&amp;', '&')
        text = text.replace('&lt;', '<').replace('&gt;', '>')
        text = text.replace('&quot;', '"').replace('&#39;', "'")
        
        # Remove extra whitespace
        text = re.sub(r'\s+', ' ', text)
        
        return text.strip()
    
    def _extract_subject(self, overview: str) -> str:
        """Extract the main subject from AI Overview."""
        if not overview:
            return "Unknown"
        
        # Try to extract the main subject
        patterns = [
            r'(?:shows|features|of|is a|is an?)\s+([^.,!?]{5,60})',
            r'(?:image|photo|picture) of (?:a|an) ([^.,!?]{5,60})',
            r'^([^.,!?]{10,60})[.,]',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, overview, re.IGNORECASE)
            if match:
                subject = match.group(1).strip()
                if 3 < len(subject) < 100:
                    return subject
        
        # Return first 50 chars
        return overview[:60].split('.')[0].strip()
    
    def _error_response(self, message: str) -> dict:
        """Return error response."""
        return {
            "success": False,
            "ai_overview": None,
            "object_name": "Unknown",
            "error": message,
            "source": "Error"
        }


# Create service instance
google_lens_service = GoogleLensService()