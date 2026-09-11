// FAQ Knowledge Base and Intent Search Engine for NexAround & Neva AI Concierge

export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=com.nexaround.app&pli=1';
export const APP_STORE_URL = 'https://apps.apple.com/lk/app/nexaround/id6806252363';

export const FAQ_CATEGORIES = [
  { id: 'all', label: 'All Topics' },
  { id: 'general', label: 'About & Getting Started' },
  { id: 'ar', label: 'Spatial AR Scanner' },
  { id: 'neva', label: 'Neva AI Concierge' },
  { id: 'odyssey', label: 'Odyssey Trip Planner' },
  { id: 'radar', label: 'Maps & Radar' },
  { id: 'bookings', label: 'Bookings & Tickets' },
  { id: 'privacy', label: 'Privacy & Security' },
];

export const FAQ_ITEMS = [
  {
    id: 'what-is-nexaround',
    category: 'general',
    question: 'What is NexAround?',
    shortAnswer: 'NexAround is a next-generation AI and Augmented Reality smart tourism companion designed to revolutionize how you explore the world.',
    answer: `NexAround is a smart tourism AI & Spatial Augmented Reality platform. It combines real-time camera computer vision for landmark recognition, the Odyssey multi-day trip planning engine, and Neva—your 24/7 intelligent travel concierge—into a single mobile application available for iOS and Android.`,
    keywords: ['what is', 'overview', 'about', 'introduction', 'how it works', 'nexaround app', 'explain'],
    actionLinks: [
      { text: 'Explore App Features', url: '/app' },
      { text: 'Download App', url: '/get-app' }
    ],
    relatedIds: ['is-it-free', 'supported-devices', 'neva-capabilities']
  },
  {
    id: 'is-it-free',
    category: 'general',
    question: 'Is NexAround free to download and use?',
    shortAnswer: 'Yes! NexAround is 100% free to download on both Apple App Store and Google Play Store.',
    answer: `Yes, NexAround is completely free to download on iOS and Android. You can start exploring landmarks with AR, chat with Neva AI, generate basic itineraries with Odyssey, and browse travel stories right away without any upfront subscription or credit card requirement.`,
    keywords: ['free', 'cost', 'pricing', 'subscription', 'price', 'pay', 'charge', 'money', 'trial', 'fee'],
    actionLinks: [
      { text: 'Download on App Store', url: APP_STORE_URL },
      { text: 'Get on Google Play', url: PLAY_STORE_URL },
      { text: 'Get App Overview', url: '/get-app' }
    ],
    relatedIds: ['what-is-nexaround', 'supported-devices']
  },
  {
    id: 'supported-devices',
    category: 'general',
    question: 'Which devices and operating systems are supported?',
    shortAnswer: 'NexAround supports iOS devices running iOS 15+ and Android devices running Android 9.0 (Pie) or higher.',
    answer: `NexAround is optimized for modern mobile hardware. For iOS, it supports iPhone 8 and newer running iOS 15.0 or later with ARKit support. For Android, it supports devices running Android 9.0+ with ARCore compatibility for real-time spatial AR tracking.`,
    keywords: ['devices', 'ios', 'android', 'iphone', 'samsung', 'compatibility', 'requirements', 'system', 'download', 'phone'],
    actionLinks: [
      { text: 'Download on App Store', url: APP_STORE_URL },
      { text: 'Get on Google Play', url: PLAY_STORE_URL }
    ],
    relatedIds: ['what-is-nexaround', 'how-ar-works']
  },
  {
    id: 'destinations-available',
    category: 'general',
    question: 'Where can I use NexAround? Which cities/countries are supported?',
    shortAnswer: 'NexAround works globally across major destinations in Europe, Asia, the Americas, and beyond.',
    answer: `NexAround works worldwide! We have rich spatial landmark data and museum guides across top global destinations including Paris, Rome, Tokyo, London, New York, Cairo, Sigiriya, Florence, Sydney, Rio de Janeiro, and hundreds more cities. Neva AI and Odyssey trip planning work anywhere on the planet!`,
    keywords: ['destinations', 'cities', 'countries', 'where', 'paris', 'rome', 'tokyo', 'global', 'locations', 'available'],
    actionLinks: [
      { text: 'Explore App Features', url: '/app' },
      { text: 'Download App', url: '/get-app' }
    ],
    relatedIds: ['what-is-nexaround', 'odyssey-how-it-works']
  },
  {
    id: 'how-ar-works',
    category: 'ar',
    question: 'How does the Spatial AR Landmark Scanner work?',
    shortAnswer: 'Raise your camera toward any monument, historic building, or outdoor landmark to get sub-second identification and spatial context.',
    answer: `Simply open the NexAround camera scanner and point your phone at any monument, historic building, cathedral, temple, or outdoor statue. Our sub-500ms computer vision neural engine matches visual features against global spatial datasets to overlay historical facts, architectural stories, and spatial details directly onto your camera screen.`,
    keywords: ['ar', 'camera', 'scan', 'landmark', 'augmented reality', 'vision', 'monuments', 'statue', 'temple', 'recognition', 'scanner'],
    actionLinks: [
      { text: 'View AR Technology', url: '/app#camera' }
    ],
    relatedIds: ['museum-artwork', 'privacy-data']
  },
  {
    id: 'museum-artwork',
    category: 'ar',
    question: 'Does NexAround include museum information and landmark guides?',
    shortAnswer: 'Yes! NexAround includes curated landmark guides, visiting details, and ticket bookings for top cultural institutions.',
    answer: `Yes! NexAround features curated destination information and skip-the-line ticket bookings for top global museums and heritage sites (such as Musée d’Orsay, the Louvre, Uffizi, or Vatican Museums). Please note that the AR camera visual scanner is designed for outdoor monuments, historic buildings, and architectural structures rather than individual indoor paintings or museum gallery exhibits.`,
    keywords: ['museum', 'landmark', 'monument', 'heritage', 'tickets', 'louvre', 'exhibits', 'guides'],
    actionLinks: [
      { text: 'Museum Guides', url: '/app#museum' }
    ],
    relatedIds: ['how-ar-works', 'neva-capabilities']
  },
  {
    id: 'neva-capabilities',
    category: 'neva',
    question: 'What is Neva AI and what can she help me with?',
    shortAnswer: 'Neva is your 24/7 personal AI travel concierge with voice and text capabilities.',
    answer: `Neva is your 24/7 intelligent travel companion built into the app. She can:
• Answer questions about what you are seeing around you.
• Recommend authentic local food, cafes, and hidden scenic spots.
• Filter recommendations by your dietary preferences (vegan, halal, gluten-free, allergies).
• Provide local cultural context and destination information.
• Provide emergency assistance, embassy contacts, and safety tips.
• Dynamically adjust your Odyssey itinerary when your plans change.`,
    keywords: ['neva', 'ai', 'concierge', 'assistant', 'chat', 'voice', 'food recommendations', 'safety', 'features', 'help'],
    actionLinks: [
      { text: 'Meet Neva AI', url: '/app#neva' }
    ],
    relatedIds: ['odyssey-how-it-works', 'privacy-data']
  },
  {
    id: 'neva-languages',
    category: 'neva',
    question: 'What languages does NexAround support?',
    shortAnswer: 'NexAround is currently available in English, with multi-language support actively on our future product roadmap.',
    answer: `NexAround currently operates in English. Multi-language support and live translation across global languages are part of our upcoming product roadmap to make travel even more accessible worldwide.`,
    keywords: ['languages', 'translation', 'multilingual', 'english', 'roadmap', 'language support'],
    actionLinks: [
      { text: 'Learn About Neva', url: '/app#neva' }
    ],
    relatedIds: ['neva-capabilities']
  },
  {
    id: 'odyssey-how-it-works',
    category: 'odyssey',
    question: 'How does the Odyssey AI Travel Planner create itineraries?',
    shortAnswer: 'Odyssey builds time-optimized, multi-day routes tailored to your travel mood, budget, dates, and live venue hours.',
    answer: `Odyssey uses generative AI and spatial route optimization algorithms. When you input your destination, travel duration, budget tier (Backpacker to Luxury), and travel mood (Adventurous, Relaxed, Cultural, or Foodie), Odyssey crafts an hour-by-hour itinerary that minimizes travel transit times and checks live opening hours. You can customize, swap stops, or export directly to Google Maps and Apple Maps with one tap.`,
    keywords: ['odyssey', 'itinerary', 'trip planner', 'multi-day', 'schedule', 'route', 'budget', 'google maps', 'apple maps', 'plan trip'],
    actionLinks: [
      { text: 'Odyssey Trip Planner', url: '/app#odyssey' }
    ],
    relatedIds: ['mood-planner', 'bookings-tickets']
  },
  {
    id: 'mood-planner',
    category: 'odyssey',
    question: 'What is the Mood-Based Journey Planner?',
    shortAnswer: 'Match your travel day to how you feel: Adventure, Chill, Romantic, Cultural, or Foodie.',
    answer: `Sometimes you don’t have a rigid destination in mind, just a vibe! Select your current mood—such as "Energized & Adventurous", "Quiet & Relaxed", "Romantic Evening", or "Hungry Foodie"—and NexAround immediately reshapes your nearby suggestions and day plan to match your energy level and current weather.`,
    keywords: ['mood', 'vibe', 'adventure', 'romantic', 'relaxed', 'feeling', 'weather'],
    actionLinks: [
      { text: 'Explore Mood Planner', url: '/app#mood' }
    ],
    relatedIds: ['odyssey-how-it-works', 'radar-discovery']
  },
  {
    id: 'radar-discovery',
    category: 'radar',
    question: 'What is the Around You Proximity Radar?',
    shortAnswer: 'A live interactive 360° radar highlighting attractions, local food stalls, and essentials around your GPS position.',
    answer: `The Smart Tourism Radar acts as your real-time spatial awareness tool. It displays dynamic rings around your current location showcasing:
• Top-rated authentic street food & verified culinary gems
• Historical landmarks within walking distance
• Real-time crowd density and best visiting hours
• Essential services: pharmacies, medical centers, transit hubs, and embassies.`,
    keywords: ['radar', 'maps', 'around me', 'proximity', 'gps', 'nearby', 'crowds', 'pharmacy', 'walking', 'map'],
    actionLinks: [
      { text: 'See Radar Features', url: '/app#radar' }
    ],
    relatedIds: ['bookings-tickets', 'privacy-data']
  },
  {
    id: 'bookings-tickets',
    category: 'bookings',
    question: 'Can I book museum tickets, hotels, and taxis directly in NexAround?',
    shortAnswer: 'Yes! NexAround integrates official skip-the-line tickets, hotel accommodations, and taxi services directly into your itinerary flow.',
    answer: `Yes! We partner with leading global travel providers:
• Official skip-the-line attraction & museum tickets via Viator, GetYourGuide, and Headout.
• Hotel & boutique stay reservations seamlessly embedded into your trip stops.
• One-tap Uber and local taxi hailing directly from your current landmark to your next destination.`,
    keywords: ['tickets', 'booking', 'viator', 'getyourguide', 'headout', 'uber', 'hotel', 'taxi', 'skip the line', 'reserve'],
    actionLinks: [
      { text: 'View Integrated Bookings', url: '/app#bookings' }
    ],
    relatedIds: ['odyssey-how-it-works', 'radar-discovery']
  },
  {
    id: 'internet-requirement',
    category: 'privacy',
    question: 'Does NexAround require an active internet connection?',
    shortAnswer: 'Yes, NexAround requires an active cellular data or Wi-Fi connection for real-time spatial AR vision and AI concierge.',
    answer: `Yes, NexAround requires an active cellular data (4G/5G) or Wi-Fi internet connection to perform real-time camera spatial recognition, stream live travel recommendations from Neva AI, and update itinerary logistics.`,
    keywords: ['internet', 'connection', 'cellular', 'wifi', 'data connection', 'online', 'requirements', 'offline'],
    actionLinks: [
      { text: 'Get App', url: '/get-app' }
    ],
    relatedIds: ['privacy-data', 'supported-devices']
  },
  {
    id: 'privacy-data',
    category: 'privacy',
    question: 'How does NexAround handle my camera feed and location privacy?',
    shortAnswer: 'Your privacy is paramount. Camera frames are processed for landmark recognition and not stored or sold.',
    answer: `We adhere strictly to global privacy standards (GDPR, CCPA). Camera video streams are analyzed locally and securely in real-time to detect landmarks—we never record or store private video footage. Your GPS location is used solely to provide relevant nearby recommendations and is never sold to third-party advertisers.`,
    keywords: ['privacy', 'security', 'camera permissions', 'location data', 'gps tracking', 'gdpr', 'safe', 'data'],
    actionLinks: [
      { text: 'Read Privacy Policy', url: '/privacy' },
      { text: 'Terms of Service', url: '/terms' }
    ],
    relatedIds: ['internet-requirement', 'how-ar-works']
  },
  {
    id: 'contact-support',
    category: 'general',
    question: 'How can I get human support or partner with NexAround?',
    shortAnswer: 'Reach our team via email at support@nexaround.com or through our dedicated Contact page.',
    answer: `Our dedicated support and partnerships team is available 24/7. You can email us at support@nexaround.com or visit our Contact page to submit custom inquiries, enterprise DMO partnerships, or feedback.`,
    keywords: ['contact', 'support', 'help', 'email', 'partner', 'human', 'feedback', 'issue', 'reach out', 'call'],
    actionLinks: [
      { text: 'Contact Us', url: '/contact' }
    ],
    relatedIds: ['what-is-nexaround']
  }
];

// Quick Starter Suggestions for the Chatbot
export const STARTER_PROMPTS = [
  'How does the AR camera scanner work?',
  'What can Neva AI do for me?',
  'How does Odyssey build itineraries?',
  'Is NexAround free to download?',
  'Does NexAround require internet?',
  'How do I book skip-the-line tickets?',
  'Which devices are supported?'
];

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
      text: `Hello there! 👋 I'm **Neva**, your 24/7 NexAround AI Travel Concierge.\n\nI'm here to help with anything regarding the **NexAround app**, **AR Landmark Scanning**, **Odyssey Trip Planner**, **smart live navigation**, **museum guides**, or **ticket bookings**.\n\nWhat can I help you discover today?`,
      actionLinks: [
        { text: 'Explore App Features', url: '/app' },
        { text: 'Download App', url: '/get-app' }
      ],
      suggestions: [
        'How does the AR camera scanner work?',
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
      text: `I'm **Neva**, the 24/7 AI travel concierge built right into the **NexAround** mobile app! 🌟\n\nI help travelers around the globe by:\n• Identifying landmarks through your camera using Spatial AR\n• Crafting custom multi-day travel itineraries with Odyssey\n• Recommending authentic local restaurants and secret viewpoints\n• Discovering local culture and neighborhood insights\n• Providing 24/7 safety and navigation assistance.`,
      actionLinks: [
        { text: 'Meet Neva AI on App Page', url: '/app#neva' },
        { text: 'Download App', url: '/get-app' }
      ],
      suggestions: [
        'How does the AR camera work?',
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
        'Can I book museum tickets?',
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
        'How does the AR camera scanner work?',
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
    text: `That's an interesting question! While I might not have a specific preset article for that exact phrase, here is what **NexAround** offers:\n\n• **Spatial AR Landmark Scanner**: Point your camera at any monument or historic building for instant history.\n• **Odyssey AI Trip Engine**: Automatically generates time-optimized travel schedules based on your budget & mood.\n• **Neva 24/7 Concierge**: Real-time voice/text assistance anywhere you travel.\n\nWould you like to explore any of these topics, or contact our support team?`,
    actionLinks: [
      { text: 'View App Features', url: '/app' },
      { text: 'Contact Support', url: '/contact' }
    ],
    suggestions: [
      'What is NexAround?',
      'How does the AR camera scanner work?',
      'Is NexAround free to download?',
      'How does Odyssey create itineraries?',
      'How do I contact human support?'
    ]
  };
}
