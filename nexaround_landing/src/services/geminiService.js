// Google Gemini AI Service for NexAround & Neva AI Concierge
import { generateNevaResponse } from '../data/faqData';

const GEMINI_API_KEY = import.meta.env.VITE_GEMINI_API_KEY || '';

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
8. Privacy & Safety: Camera stream is processed locally for landmark recognition and never stored/recorded. GPS is private and never sold to third-party advertisers. GDPR & CCPA compliant. Works offline with downloadable city packs.

RESPONSE GUIDELINES:
- Tone: Welcoming, adventurous, articulate, concise, and helpful.
- Formatting: Use standard markdown with bold highlights and clean bullet points where appropriate.
- Keep responses focused (under 120-150 words unless detailed itinerary is requested).
- If the user asks about app downloads or features, mention they can explore the app features or download free on iOS/Android.
`;

const GEMINI_MODELS = [
  'gemini-2.5-flash',
  'gemini-1.5-flash',
  'gemini-2.0-flash',
  'gemini-2.5-flash-lite'
];

/**
 * Ask Google Gemini AI with conversation context and system instructions.
 * Falls back seamlessly to the local FAQ engine if no API key is configured or on network failure.
 */
export async function askGemini(prompt, conversationHistory = []) {
  if (!prompt || !prompt.trim()) {
    return {
      text: "Please ask a question about NexAround or travel destinations!",
      suggestions: ['How does the AR camera scanner work?', 'How does Odyssey build itineraries?', 'Is NexAround free?']
    };
  }

  // If no Gemini API key is configured, use the smart local FAQ engine
  if (!GEMINI_API_KEY || GEMINI_API_KEY.trim() === '' || GEMINI_API_KEY === 'your_gemini_api_key_here') {
    return generateNevaResponse(prompt);
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

  // Try available Gemini models with fallback
  for (const model of GEMINI_MODELS) {
    try {
      const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`;

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          contents: contents,
          generationConfig: {
            temperature: 0.7,
            topK: 40,
            topP: 0.95,
            maxOutputTokens: 600,
          }
        })
      });

      if (!response.ok) {
        continue;
      }

      const data = await response.json();
      const candidateText = data.candidates?.[0]?.content?.parts?.[0]?.text;

      if (candidateText && candidateText.trim()) {
        const actionLinks = [];
        const lowerText = candidateText.toLowerCase();
        if (lowerText.includes('download') || lowerText.includes('get app') || lowerText.includes('free to download')) {
          actionLinks.push({ text: 'Download App', url: '/get-app' });
        }
        if (lowerText.includes('ar') || lowerText.includes('landmark') || lowerText.includes('scanner') || lowerText.includes('camera')) {
          actionLinks.push({ text: 'AR Features', url: '/app#camera' });
        }
        if (lowerText.includes('odyssey') || lowerText.includes('itinerary') || lowerText.includes('planner')) {
          actionLinks.push({ text: 'Odyssey Planner', url: '/app#odyssey' });
        }

        return {
          text: candidateText.trim(),
          actionLinks: actionLinks.slice(0, 2),
          isGeminiPowered: true,
          suggestions: [
            'How does the AR camera work?',
            'How does Odyssey plan trips?',
            'Is NexAround free to download?',
            'Does NexAround work offline?'
          ]
        };
      }
    } catch (err) {
      console.warn(`Error trying Gemini model ${model}:`, err);
    }
  }

  // Fallback to local FAQ engine
  return generateNevaResponse(prompt);
}

export function isGeminiConfigured() {
  return Boolean(GEMINI_API_KEY && GEMINI_API_KEY.trim() !== '' && GEMINI_API_KEY !== 'your_gemini_api_key_here');
}
