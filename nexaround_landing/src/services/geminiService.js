// Neva AI Concierge service.
// The Gemini API key is NEVER shipped to the browser. This calls our own
// backend (which holds the key server-side, like the mobile app does); the
// backend proxies to Gemini. On any failure we fall back to the local FAQ
// engine, so the widget always answers. (Security finding NA-02.)
import { generateNevaResponse } from '../data/faqData';

const NEVA_API_URL = 'https://api.nexaround.com/api/v1/landing/neva';

// System instruction with complete NexAround domain knowledge
const NEVA_SYSTEM_INSTRUCTION = `
You are Neva, the AI travel companion of the nexARound app, answering visitors on the nexARound website.
Help visitors understand what the app does, and answer general travel questions.

WHAT THE APP DOES (describe only these, never invent features):
1. nexARound: a free AI travel companion app for iOS 15.5+ and Android 7.0+, by NEXAROUND TECHNOLOGIES LLC.
2. AR Discovery: hold up the phone to see nearby places over the camera view (food, shops, hotels, nature, medical). Pointing at a place shows what it is, from GPS location and compass. Tap Neva for a short description. AR walking routes show direction arrows. It does NOT recognise buildings, paintings or objects from the camera image.
3. Neva in the app: chat or talk by voice about places, food, history, budgets and what to do next, based on location. Suggested places appear on a map with directions.
4. Odyssey AI Planner: a day-by-day trip plan from destination, dates, travellers, budget and nationality, with flight and hotel options, a budget breakdown, visa guidance and a booking timeline. Places can be reordered and ticked off, and spending recorded.
5. City Guides: day-by-day city guides by creators, reviewed by nexARound, with live navigation and public transport directions, in a growing list of cities.
6. Where Should I Go Today?: pick a mood, location, weather, time, company and a mode such as Food Quest or Photo Hunt, and Neva plans nearby stops for today.
7. Local Experiences: activities by local providers. The traveller sends a request, the provider confirms or offers another date, and the traveller pays the provider at the experience.
8. Museum Master Guides: 50+ leading museums, routes from 3 hours to 2 days, opening hours, skip-the-line ticket links.
9. Also: Walking Challenge (check in at sights, earn XP), 3D Smart Map with turn-by-turn navigation, Discover (nearby places by category), emergency numbers and phrases, Travel Stories, Travel Forum, private Travel Journal.
10. Bookings: links to partners for flights, stays, tours, airport cars, eSIMs, insurance and luggage storage. Visitors book and pay on the partner's site; nexARound takes no payment for these.
11. Privacy: the AR camera view stays on the device and is not recorded. Neva Voice recordings go to nexARound's servers and its AI provider. Location is never sold.
12. The app is in English and needs internet for most features. Support: support@nexaround.com or the Contact page.

RESPONSE GUIDELINES:
- Welcoming, concise and helpful. Short markdown with bold and bullets where useful.
- Under 120 words unless the visitor asks for detail.
- If asked about something not listed above (for example camera landmark recognition, offline maps, in-app hotel payment or other languages), say plainly that the app does not offer it.
- For downloads, say the app is free on iOS and Android.
`;

/**
 * Ask Neva (via our backend) with conversation context and system instructions.
 * Falls back seamlessly to the local FAQ engine on any network/backend failure.
 */
export async function askGemini(prompt, conversationHistory = []) {
  if (!prompt || !prompt.trim()) {
    return {
      text: "Please ask a question about NexAround or travel destinations!",
      suggestions: ['How does AR Discovery work?', 'How does Odyssey build itineraries?', 'Is NexAround free?']
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
          actionLinks.push({ text: 'Apple App Store', url: 'https://apps.apple.com/app/nexaround/id6806252363' });
        }
        if (lowerText.includes('google play') || lowerText.includes('play store') || lowerText.includes('android')) {
          actionLinks.push({ text: 'Google Play Store', url: 'https://play.google.com/store/apps/details?id=com.nexaround.app&pli=1' });
        }
        if (lowerText.includes('download') || lowerText.includes('get app') || lowerText.includes('free to download')) {
          actionLinks.push({ text: 'Download Overview', url: '/get-app' });
        }
        if (lowerText.includes('ar') || lowerText.includes('landmark') || lowerText.includes('scanner') || lowerText.includes('camera')) {
          actionLinks.push({ text: 'AR Discovery', url: '/app#ar' });
        }
        if (lowerText.includes('odyssey') || lowerText.includes('itinerary') || lowerText.includes('planner')) {
          actionLinks.push({ text: 'Odyssey Planner', url: '/app#odyssey' });
        }

        return {
          text: candidateText.trim(),
          actionLinks: actionLinks.slice(0, 3),
          isGeminiPowered: true,
          suggestions: [
            'How does AR Discovery work?',
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
