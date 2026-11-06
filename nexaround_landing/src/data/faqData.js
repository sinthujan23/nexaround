// FAQ Knowledge Base and Intent Search Engine for NexAround & Neva AI Concierge

export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.nexaround.app&pli=1';
export const APP_STORE_URL = 'https://apps.apple.com/app/nexaround/id6806252363';

export const FAQ_CATEGORIES = [
  { id: 'all', label: 'All Topics' },
  { id: 'general', label: 'About & Getting Started' },
  { id: 'ar', label: 'AR Discovery' },
  { id: 'neva', label: 'Neva AI' },
  { id: 'odyssey', label: 'Trip Planning' },
  { id: 'guides', label: 'City Guides & Museums' },
  { id: 'radar', label: 'Maps & Discover' },
  { id: 'bookings', label: 'Bookings & Experiences' },
  { id: 'privacy', label: 'Privacy & Security' },
]

export const FAQ_ITEMS = [
  {
    id: "what-is-nexaround",
    category: "general",
    question: "What is nexARound?",
    shortAnswer: "nexARound is an AI-powered travel companion app for iOS and Android.",
    answer: "nexARound helps you plan a trip, discover what is around you and book local experiences anywhere in the world. It brings together the Odyssey AI trip planner, AR Discovery, City Guides, Where Should I Go Today?, local experiences, travel stories and Neva, your AI travel companion, in one free app.",
    keywords: ["what is", "overview", "about", "introduction", "how it works", "nexaround app", "explain", "features"],
    actionLinks: [
      { text: "Explore App Features", url: "/app" },
      { text: "Download App", url: "/get-app" }
    ],
    relatedIds: ["is-it-free", "city-guides", "neva-capabilities"]
  },
  {
    id: "is-it-free",
    category: "general",
    question: "Is nexARound free to download and use?",
    shortAnswer: "Yes. nexARound is free to download on the App Store and Google Play.",
    answer: "Yes. nexARound is free to download on iOS and Android, with no subscription. Flights, stays, tours and local experiences are paid to the partner or provider you book with.",
    keywords: ["free", "cost", "pricing", "subscription", "price", "pay", "charge", "money", "trial", "fee"],
    actionLinks: [
      { text: "Download on App Store", url: APP_STORE_URL },
      { text: "Get on Google Play", url: PLAY_STORE_URL },
      { text: "Get App Overview", url: "/get-app" }
    ],
    relatedIds: ["what-is-nexaround", "supported-devices"]
  },
  {
    id: "supported-devices",
    category: "general",
    question: "Which devices and operating systems are supported?",
    shortAnswer: "iPhones with iOS 15.5 or later, and Android phones with Android 7.0 or later.",
    answer: "nexARound runs on iPhones with iOS 15.5 or later and on Android phones with Android 7.0 or later. AR Discovery uses your camera, GPS and compass.",
    keywords: ["devices", "ios", "android", "iphone", "samsung", "compatibility", "requirements", "system", "download", "phone"],
    actionLinks: [
      { text: "Download on App Store", url: APP_STORE_URL },
      { text: "Get on Google Play", url: PLAY_STORE_URL }
    ],
    relatedIds: ["what-is-nexaround", "how-ar-works"]
  },
  {
    id: "destinations-available",
    category: "general",
    question: "Where can I use nexARound?",
    shortAnswer: "nexARound works anywhere in the world.",
    answer: "Odyssey, Neva, AR Discovery, maps and Where Should I Go Today? work anywhere in the world. City Guides and local experiences are available in a growing list of cities and countries, and Museum Master Guides cover more than 50 leading museums.",
    keywords: ["destinations", "cities", "countries", "where", "paris", "rome", "tokyo", "global", "locations", "available"],
    actionLinks: [
      { text: "Explore App Features", url: "/app" },
      { text: "Download App", url: "/get-app" }
    ],
    relatedIds: ["city-guides", "odyssey-how-it-works"]
  },
  {
    id: "how-ar-works",
    category: "ar",
    question: "How does AR Discovery work?",
    shortAnswer: "Hold up your phone to see nearby places over the camera view.",
    answer: "Open the AR tab and look around. nexARound uses your location and compass to show nearby places over the camera view, such as food, shops, hotels, nature and medical services. Point your phone at a place to see what it is, tap Neva for a short description, or start a walking route with direction arrows. AR Discovery finds places from your location; it does not recognise buildings from the camera image.",
    keywords: ["ar", "camera", "scan", "landmark", "augmented reality", "vision", "monuments", "statue", "temple", "recognition", "scanner", "point"],
    actionLinks: [
      { text: "AR Discovery", url: "/app#ar" }
    ],
    relatedIds: ["museum-artwork", "privacy-data"]
  },
  {
    id: "neva-capabilities",
    category: "neva",
    question: "What is Neva and what can she help me with?",
    shortAnswer: "Neva is the AI travel companion in the app, by text or voice.",
    answer: "Neva is the AI travel companion built into the app. She can:\n• Answer questions about places, food, history, budgets and what to do next, based on your location.\n• Show the places she suggests on a map, with directions.\n• Talk with you by voice and read her replies aloud.\n• Take you to the right tool, such as AR or Odyssey.",
    keywords: ["neva", "ai", "concierge", "assistant", "chat", "voice", "food recommendations", "safety", "features", "help"],
    actionLinks: [
      { text: "Meet Neva", url: "/app#neva" }
    ],
    relatedIds: ["where-should-i-go", "privacy-data"]
  },
  {
    id: "neva-languages",
    category: "neva",
    question: "What languages does nexARound support?",
    shortAnswer: "The app is currently in English.",
    answer: "The nexARound app is currently in English. Language settings are coming soon.",
    keywords: ["languages", "translation", "multilingual", "english", "roadmap", "language support"],
    actionLinks: [
      { text: "Learn About Neva", url: "/app#neva" }
    ],
    relatedIds: ["neva-capabilities"]
  },
  {
    id: "odyssey-how-it-works",
    category: "odyssey",
    question: "How does the Odyssey AI Planner create a trip plan?",
    shortAnswer: "Odyssey builds a day-by-day plan from your destination, dates, travellers and budget.",
    answer: "Enter your destination, dates, number of travellers, budget and nationality. Odyssey builds a complete day-by-day plan, with flight and hotel options, a line-by-line budget breakdown, visa guidance and a timeline of what to book first. For trips across several cities you can preview and compare routes. Then drag places to reorder them, tick off what you visit and record what you spend.",
    keywords: ["odyssey", "itinerary", "trip planner", "multi-day", "schedule", "route", "budget", "visa", "flights", "plan trip"],
    actionLinks: [
      { text: "Odyssey AI Planner", url: "/app#odyssey" }
    ],
    relatedIds: ["where-should-i-go", "bookings-tickets"]
  },
  {
    id: "where-should-i-go",
    category: "odyssey",
    question: "What is Where Should I Go Today?",
    shortAnswer: "Tell nexARound your mood and get a plan for today.",
    answer: "Where Should I Go Today? plans your day from how you feel. Choose your mood, your location, the weather, the time you have and who you are with, then pick a mode such as Food Quest, Photo Hunt or Surprise Me. Neva builds a plan of nearby stops with arrival times, tips and food suggestions, and sends a notification when it is ready. Your past plans stay in History.",
    keywords: ["mood", "vibe", "today", "where should i go", "feeling", "weather", "plan my day", "day plan", "romantic", "relaxed"],
    actionLinks: [
      { text: "Where Should I Go Today?", url: "/app#today" }
    ],
    relatedIds: ["odyssey-how-it-works", "city-guides"]
  },
  {
    id: "city-guides",
    category: "guides",
    question: "What are City Guides?",
    shortAnswer: "Day-by-day city guides with live navigation.",
    answer: "City Guides are day-by-day guides to cities, written by creators and reviewed by nexARound, with sights, rides, breaks and photos. Plan by day or by place, tick off sights as you visit them and get reminders during the trip. Press Start on a walk or ride for live directions, including which public transport line to take.",
    keywords: ["city guide", "city guides", "guide", "walking tour", "tour", "navigation", "public transport", "metro", "sightseeing"],
    actionLinks: [
      { text: "City Guides", url: "/app#city-guides" }
    ],
    relatedIds: ["museum-artwork", "where-should-i-go"]
  },
  {
    id: "museum-artwork",
    category: "guides",
    question: "Does nexARound have museum guides?",
    shortAnswer: "Yes. Museum Master Guides cover more than 50 leading museums.",
    answer: "Yes. Museum Master Guides cover more than 50 leading museums, such as the Louvre, the Uffizi and the Vatican Museums. Choose your time, from 3 hours to 2 days, and follow a route through the masterpieces, with opening hours and skip-the-line ticket links. Itineraries are still being added for some museums.",
    keywords: ["museum", "museums", "gallery", "heritage", "tickets", "louvre", "exhibits", "masterpieces"],
    actionLinks: [
      { text: "Museum Guides", url: "/app#museums" }
    ],
    relatedIds: ["city-guides", "how-ar-works"]
  },
  {
    id: "radar-discovery",
    category: "radar",
    question: "How do I find places near me?",
    shortAnswer: "Use Discover, the Smart Map or AR to see what is nearby.",
    answer: "Discover lists nearby places by category: points of interest, nature, food, shopping, medical and hospitals. The 3D Smart Map lets you search any location, get driving or walking directions and start turn-by-turn navigation. If you need help, the emergency button on Home gives you local emergency numbers, useful phrases and nearby hospitals.",
    keywords: ["radar", "maps", "map", "around me", "nearby", "gps", "discover", "pharmacy", "hospital", "emergency", "directions", "navigation"],
    actionLinks: [
      { text: "Smart Maps", url: "/app#maps" },
      { text: "Discover", url: "/app#discover" }
    ],
    relatedIds: ["how-ar-works", "privacy-data"]
  },
  {
    id: "bookings-tickets",
    category: "bookings",
    question: "Can I book hotels, flights, tickets and taxis through nexARound?",
    shortAnswer: "nexARound links you to trusted partners, and you book on their site or app.",
    answer: "Your Odyssey plan links to travel partners for flights, stays, tours and airport cars, with eSIMs, travel insurance and luggage storage where available. You book and pay on the partner's site or app. Museum guides link to skip-the-line tickets, and ride app suggestions show which taxi apps work in your destination.",
    keywords: ["tickets", "booking", "book", "viator", "getyourguide", "uber", "hotel", "flight", "taxi", "skip the line", "reserve", "esim", "insurance"],
    actionLinks: [
      { text: "Booking Partners", url: "/app#partners" }
    ],
    relatedIds: ["experiences-booking", "odyssey-how-it-works"]
  },
  {
    id: "experiences-booking",
    category: "bookings",
    question: "How do I book a local experience?",
    shortAnswer: "Send a request in the app. The provider confirms, and you pay them at the experience.",
    answer: "Open Experiences to browse activities run by local providers, near you or by country. Choose a date, your group size and pickup, then send a request. The provider confirms your date or offers another one, and you can follow or cancel your request in My Requests. You pay the provider directly at the experience. The Experience Booking Terms explain cancellations.",
    keywords: ["experience", "experiences", "activity", "activities", "safari", "boat", "provider", "request", "cancel", "operator"],
    actionLinks: [
      { text: "Local Experiences", url: "/app#experiences" },
      { text: "Experience Booking Terms", url: "/experience-terms" }
    ],
    relatedIds: ["bookings-tickets", "contact-support"]
  },
  {
    id: "internet-requirement",
    category: "privacy",
    question: "Does nexARound need an internet connection?",
    shortAnswer: "Yes. Most features need mobile data or Wi-Fi.",
    answer: "Yes. AR place labels, Neva, Odyssey, maps and City Guides need a mobile data or Wi-Fi connection to load places, directions and answers.",
    keywords: ["internet", "connection", "cellular", "wifi", "data connection", "online", "requirements", "offline"],
    actionLinks: [
      { text: "Get App", url: "/get-app" }
    ],
    relatedIds: ["privacy-data", "supported-devices"]
  },
  {
    id: "privacy-data",
    category: "privacy",
    question: "How does nexARound handle my camera, microphone and location?",
    shortAnswer: "The AR camera view stays on your device, and your location is never sold.",
    answer: "The live AR camera view stays on your device and is not recorded or sent to our servers. The microphone is used only when you search by voice or talk to Neva; Neva Voice recordings are sent to our servers and our AI provider to understand your question. Your location is used to show nearby places and directions, and is never sold to advertisers. The Privacy Policy has the details.",
    keywords: ["privacy", "security", "camera permissions", "microphone", "voice", "location data", "gps tracking", "safe", "data"],
    actionLinks: [
      { text: "Read Privacy Policy", url: "/privacy" },
      { text: "Terms of Service", url: "/terms" }
    ],
    relatedIds: ["internet-requirement", "how-ar-works"]
  },
  {
    id: "contact-support",
    category: "general",
    question: "How can I contact support or partner with nexARound?",
    shortAnswer: "Email support@nexaround.com or use our Contact page.",
    answer: "Email support@nexaround.com or send a message from our Contact page. We usually reply within one business day. Tour operators and activity providers can apply on our List your experience page. Tourism boards, museums and hotels can use the Contact page to ask about partnerships.",
    keywords: ["contact", "support", "help", "email", "partner", "human", "feedback", "issue", "reach out", "call"],
    actionLinks: [
      { text: "Contact Us", url: "/contact" },
      { text: "List Your Experience", url: "/list-your-experience" }
    ],
    relatedIds: ["what-is-nexaround"]
  }
];

// Quick Starter Suggestions for the Chatbot
export const STARTER_PROMPTS = [
  'How does AR Discovery work?',
  'What can Neva do for me?',
  'How does Odyssey plan a trip?',
  'What are City Guides?',
  'What is Where Should I Go Today?',
  'Is nexARound free to download?',
  'Which devices are supported?'
]

// Smart Natural Language & Keyword Query Matcher
export function searchFaq(query) {
  if (!query || query.trim() === '') {
    return [];
  }

  const cleanQuery = query.toLowerCase().trim();
  const queryTokens = cleanQuery.replace(/[^\w\s]/gi, '').split(/\s+/).filter(t => t.length > 1);

  // Score each FAQ item based on match relevance
  const scored = FAQ_ITEMS.map(item => {
    let score = 0;
    const questionLower = item.question.toLowerCase();
    const answerLower = item.answer.toLowerCase();
    const shortAnswerLower = item.shortAnswer.toLowerCase();

    // Exact question match
    if (questionLower === cleanQuery) score += 120;
    else if (questionLower.includes(cleanQuery)) score += 60;

    // Keyword exact matches
    item.keywords.forEach(kw => {
      if (cleanQuery === kw) score += 50;
      else if (cleanQuery.includes(kw)) score += 30;
      else if (kw.includes(cleanQuery)) score += 20;
    });

    // Token matching
    queryTokens.forEach(token => {
      if (questionLower.includes(token)) score += 18;
      if (shortAnswerLower.includes(token)) score += 12;
      if (answerLower.includes(token)) score += 6;
      item.keywords.forEach(kw => {
        if (kw.includes(token)) score += 14;
      });
    });

    return { item, score };
  });

  // Filter items with positive score and sort descending
  const results = scored
    .filter(res => res.score > 0)
    .sort((a, b) => b.score - a.score)
    .map(res => res.item);

  return results;
}

// Generates an AI Concierge conversational response for the chatbot
export function generateNevaResponse(userMessage) {
  const query = userMessage.trim().toLowerCase();

  // 1. Handle casual greetings & introductions
  const greetings = ['hi', 'hello', 'hey', 'good morning', 'good afternoon', 'good evening', 'howdy', 'greetings', 'sup', 'yo'];
  if (greetings.some(g => query === g || query.startsWith(g + ' ') || query.endsWith(' ' + g) || query.startsWith(g + '!') || query.startsWith(g + '?'))) {
    return {
      text: "Hello there! 👋 I'm **Neva**, the nexARound AI travel companion.\n\nI can help with anything about the **nexARound app**: **AR Discovery**, the **Odyssey AI Planner**, **City Guides**, **museum guides** or **local experiences**.\n\nWhat can I help you discover today?",
      actionLinks: [
        { text: 'Explore App Features', url: '/app' },
        { text: 'Download App', url: '/get-app' }
      ],
      suggestions: [
        'How does AR Discovery work?',
        'How does Odyssey build itineraries?',
        'Is NexAround free to download?',
        'Does NexAround require internet?'
      ]
    };
  }

  // 2. Handle "Who are you?" or "What can you do?"
  const identityQueries = ['who are you', 'what is your name', 'what can you do', 'what do you do', 'who made you', 'who created you', 'tell me about yourself'];
  if (identityQueries.some(q => query.includes(q))) {
    return {
      text: "I'm **Neva**, the AI travel companion built into the **nexARound** app! 🌟\n\nIn the app I help travellers by:\n• Answering questions about places, food and what to do next, based on their location\n• Showing suggested places on a map, with directions\n• Planning a day with Where Should I Go Today?\n• Talking by voice and reading replies aloud\n\nHere on the website, I can answer your questions about the app.",
      actionLinks: [
        { text: 'Meet Neva AI on App Page', url: '/app#neva' },
        { text: 'Download App', url: '/get-app' }
      ],
      suggestions: [
        'How does AR Discovery work?',
        'How does Odyssey plan trips?',
        'Is the app free to use?'
      ]
    };
  }

  // 3. Handle gratitude & praise
  const thanks = ['thank', 'thanks', 'thank you', 'awesome', 'great', 'cool', 'perfect', 'nice', 'good job'];
  if (thanks.some(t => query.includes(t))) {
    return {
      text: `You're very welcome! ✨ Traveling is all about exploring with wonder and confidence. Let me know whenever you have more questions about NexAround!`,
      suggestions: [
        'How do I download NexAround?',
        'Does nexARound have museum guides?',
        'How does location privacy work?'
      ]
    };
  }

  // 4. Handle "How are you?"
  if (query.includes('how are you') || query.includes('how r u') || query.includes('how are you doing')) {
    return {
      text: `I'm doing great and ready to help you plan your next adventure! 🌍 How can I assist you with NexAround today?`,
      suggestions: [
        'How does Odyssey plan trips?',
        'How does AR Discovery work?',
        'Is the app free to use?'
      ]
    };
  }

  // 5. Match against FAQ knowledge base
  const matches = searchFaq(userMessage);

  if (matches.length > 0) {
    const topMatch = matches[0];
    const related = matches.slice(1, 4).map(m => m.question);

    return {
      text: `**${topMatch.question}**\n\n${topMatch.answer}`,
      actionLinks: topMatch.actionLinks || [],
      matchedFaqId: topMatch.id,
      suggestions: related.length > 0 ? related : [
        'How does Odyssey build itineraries?',
        'How do I download NexAround?',
        'Does NexAround require internet?'
      ]
    };
  }

  // 6. Intelligent conversational fallback
  return {
    text: "That's a good question! I don't have a ready answer for that, but here is what **nexARound** offers:\n\n• **AR Discovery**: hold up your phone to see nearby places over the camera view.\n• **Odyssey AI Planner**: a day-by-day trip plan from your destination, dates and budget.\n• **City Guides**: day-by-day guides with live navigation.\n• **Neva**: your AI travel companion, by text or voice.\n\nWould you like to explore one of these, or contact our support team?",
    actionLinks: [
      { text: 'View App Features', url: '/app' },
      { text: 'Contact Support', url: '/contact' }
    ],
    suggestions: [
      'What is NexAround?',
      'How does AR Discovery work?',
      'Is NexAround free to download?',
      'How does Odyssey create itineraries?',
      'How do I contact human support?'
    ]
  };
}
