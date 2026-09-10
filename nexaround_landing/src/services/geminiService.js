// Neva AI Concierge service.
// The Gemini API key is NEVER shipped to the browser. This calls our own
// backend (which holds the key server-side, like the mobile app does); the
// backend proxies to Gemini. On any failure we fall back to the local FAQ
// engine, so the widget always answers. (Security finding NA-02.)
import { generateNevaResponse } from '../data/faqData';

const NEVA_API_URL = 'https://api.nexaround.com/api/v1/landing/neva';

// System instruction with complete NexAround domain knowledge
const NEVA_SYSTEM_INSTRUCTION = `
You are Neva, the official 24/7 AI Travel Concierge for the NexAround mobile application and platform.
Your mission is to help travelers, explorers, and visitors with accurate information about NexAround's features, travel advice, landmark scanning, itinerary planning, and app capabilities.

CORE NEXAROUND KNOWLEDGE:
1. What is NexAround: Next-generation Smart Tourism AI & Augmented Reality (AR) platform available on iOS and Android.
2. Spatial AR Landmark Scanner: Point camera at monuments, historic buildings, temples, statues, or museum paintings for sub-500ms real-time identification and 3D historical overlays.
3. Neva AI Travel Concierge: 24/7 voice and text intelligent assistant that understands location, recommends authentic local food/hidden spots, filters by dietary preferences, translates foreign signs, and adjusts itineraries.
4. Odyssey AI Trip Planner: Multi-day itinerary generation engine that optimizes routes, considers live opening hours, and matches budget tiers (Hostels to Luxury) and moods (Adventure, Relaxed, Romantic, Foodie). Exports to Google Maps & Apple Maps.
5. Living Radar & Maps: Real-time 360-degree proximity radar for attractions, food, crowds, and essentials.
6. Bookings & Tickets: Integrated skip-the-line museum/attraction tickets (Viator, GetYourGuide, Headout), hotel reservations, and Uber/taxi rides.
7. Pricing & Download: 100% Free to download on Apple App Store (iOS 15+) and Google Play Store (Android 9.0+). No credit card required.
8. Privacy & Safety: Camera stream is processed locally for landmark recognition and never stored/recorded. GPS is private and never sold to third-party advertisers. GDPR & CCPA compliant. Requires active internet connection for real-time spatial vision & AI guidance.

RESPONSE GUIDELINES:
- Tone: Welcoming, adventurous, articulate, concise, and helpful.
- Formatting: Use standard markdown with bold highlights and clean bullet points where appropriate.
- Keep responses focused (under 120-150 words unless detailed itinerary is requested).
- If the user asks about app downloads or features, mention they can explore the app features or download free on iOS/Android.
`;

/**
 * Ask Neva (via our backend) with conversation context and system instructions.
 * Falls back seamlessly to the local FAQ engine on any network/backend failure.
 */
export async function askGemini(prompt, conversationHistory = []) {
  if (!prompt || !prompt.trim()) {
    return {
      text: "Please ask a question about NexAround or travel destinations!",
      suggestions: ['How does the AR camera scanner work?', 'How does Odyssey build itineraries?', 'Is NexAround free?']
    };
  }

  // Convert past messages into Gemini contents format
  const contents = [
    {
      role: 'user',
      parts: [{ text: NEVA_SYSTEM_INSTRUCTION }]
    },
    {
      role: 'model',
      parts: [{ text: "Understood! I am Neva, the 24/7 AI Travel Concierge for NexAround. How can I help you explore today?" }]
    }
  ];

  // Append recent conversation history (up to last 6 messages)
  const recentHistory = conversationHistory.slice(-6);
  recentHistory.forEach((msg) => {
    if (msg.sender === 'user') {
      contents.push({
        role: 'user',
        parts: [{ text: msg.text }]
      });
    } else if (msg.sender === 'bot') {
      contents.push({
        role: 'model',
        parts: [{ text: msg.text }]
      });
    }
  });

  // Append current user prompt
  contents.push({
    role: 'user',
    parts: [{ text: prompt }]
  });

  // Call our backend (key stays server-side). One attempt; the backend handles
  // its own model fallback.
  {
    try {
      const response = await fetch(NEVA_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ contents }),
      });

      if (!response.ok) {
        // Rate limited / temporarily unavailable → local FAQ answer.
        return generateNevaResponse(prompt);
      }

      const data = await response.json();
      const candidateText = data.text;

      if (candidateText && candidateText.trim()) {
        const actionLinks = [];
        const lowerText = candidateText.toLowerCase();
        if (lowerText.includes('app store') || lowerText.includes('ios') || lowerText.includes('iphone') || lowerText.includes('apple')) {
          actionLinks.push({ text: 'Apple App Store', url: 'https://apps.apple.com/lk/app/nexaround/id6806252363' });
        }
        if (lowerText.includes('google play') || lowerText.includes('play store') || lowerText.includes('android')) {
          actionLinks.push({ text: 'Google Play Store', url: 'https://play.google.com/store/apps/details?id=com.nexaround.app&pli=1' });
        }
        if (lowerText.includes('download') || lowerText.includes('get app') || lowerText.includes('free to download')) {
          actionLinks.push({ text: 'Download Overview', url: '/get-app' });
        }
        if (lowerText.includes('ar') || lowerText.includes('landmark') || lowerText.includes('scanner') || lowerText.includes('camera')) {
          actionLinks.push({ text: 'AR Features', url: '/app#camera' });
        }
        if (lowerText.includes('odyssey') || lowerText.includes('itinerary') || lowerText.includes('planner')) {
          actionLinks.push({ text: 'Odyssey Planner', url: '/app#odyssey' });
        }

        return {
          text: candidateText.trim(),
          actionLinks: actionLinks.slice(0, 3),
          isGeminiPowered: true,
          suggestions: [
            'How does the AR camera work?',
            'How does Odyssey plan trips?',
            'Is NexAround free to download?',
            'Does NexAround require internet?'
          ]
        };
      }
    } catch (err) {
      console.warn('Neva backend call failed:', err);
    }
  }

  // Fallback to local FAQ engine
  return generateNevaResponse(prompt);
}

export function isGeminiConfigured() {
  // The key now lives on the backend; the widget is always "AI-capable" from
  // the client's point of view and degrades to the local FAQ engine on failure.
  return true;
}
