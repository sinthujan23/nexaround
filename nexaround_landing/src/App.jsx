import { useState, useRef, useEffect } from 'react';
import { 
  Sparkles, 
  Map, 
  Navigation, 
  Check, 
  Smartphone, 
  ArrowRight, 
  Bot, 
  Globe, 
  Zap,
  Menu,
  X
} from 'lucide-react';


export default function App() {
  // Navigation State
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  // Neva Chat Simulator States
  const [messages, setMessages] = useState([
    {
      sender: 'bot',
      text: '<p>👋 Hello! I am <strong>Neva</strong>, your AI Tourism Companion. Ask me anything about your next trip, or select one of the queries below to see how I can help you explore!</p>',
      time: 'Just now'
    }
  ]);
  const [isTyping, setIsTyping] = useState(false);
  const chatEndRef = useRef(null);

  // Pre-configured simulation conversations
  const conversations = {
    itinerary: {
      question: "Plan a quick 1-day itinerary for Tokyo 🗼",
      response: `
        <p>🌸 <strong>One-Day Tokyo Whirlwind Itinerary!</strong></p>
        <p>Here is your highly curated micro-itinerary designed to maximize your day:</p>
        <ul>
          <li>🌅 <strong>Morning (9:00 AM)</strong>: Start at the historic <em>Senso-ji Temple</em> in Asakusa. Grab a warm, fresh melonpan bread from local stalls!</li>
          <li>🌳 <strong>Afternoon (1:30 PM)</strong>: Take the subway to Harajuku. Walk through the peaceful, forested grounds of <em>Meiji Shrine</em>, then dive into the bustling energy of <em>Takeshita Street</em>.</li>
          <li>🍢 <strong>Evening (6:00 PM)</strong>: Capture the classic crossing shot at <em>Shibuya Crossing</em>, then grab dinner at a tiny, atmospheric Izakaya in <em>Nonbei Yokocho</em>.</li>
          <li>🏙️ <strong>Night (9:30 PM)</strong>: Ascend to <em>Shibuya Sky</em> for an open-air 360° night view of Tokyo's neon skyline. Absolutely stunning!</li>
        </ul>
        <p>💡 <em>Neva's Tip: Use our built-in Mapbox navigation card to easily buy your Tokyo subway day pass with one tap!</em></p>
      `
    },
    ar: {
      question: "How does AR Landmark Detection work? 🕶️",
      response: `
        <p>🔮 <strong>Real-time AR Landmark Identification</strong></p>
        <p>NexAround uses your device's camera and live machine learning to overlay digital info on the physical world:</p>
        <ul>
          <li>📷 <strong>Point & Scan</strong>: Aim your phone's camera at any famous landmark, building, or historical site.</li>
          <li>🏷️ <strong>Smart Labeling</strong>: The system overlays interactive tags in real-time, detailing its name, historical significance, and ratings.</li>
          <li>🚗 <strong>Seamless Actions</strong>: Click the tag to immediately access deep links like hailing an Uber directly to the entrance, booking tickets on Booking.com, or opening native navigation.</li>
        </ul>
      `
    },
    cache: {
      question: "Explain the Caching Engine optimization ⚡",
      response: `
        <p>🚀 <strong>Geospatial Caching & Battery Saving</strong></p>
        <p>NexAround is engineered to run super-fast while preserving your phone's battery during travel:</p>
        <ul>
          <li>📱 <strong>Hive Local Storage</strong>: Caches your map tiles and local locations on-device so they load instantly even if you lose internet.</li>
          <li>🛰️ <strong>GeoAlchemy2 Backend</strong>: Runs spatial database indexing (PostGIS) to find nearby attractions in under 50ms.</li>
          <li>🔋 <strong>Redis Buffering</strong>: Minimizes external API calls to Mapbox and Google by buffering common queries, saving up to 40% battery usage!</li>
        </ul>
      `
    }
  };

  const handlePromptClick = (key) => {
    if (isTyping) return;
    
    const selected = conversations[key];
    
    // Add user message
    setMessages(prev => [...prev, {
      sender: 'user',
      text: selected.question,
      time: 'Just now'
    }]);

    setIsTyping(true);

    // Simulate Neva typing
    setTimeout(() => {
      setIsTyping(false);
      setMessages(prev => [...prev, {
        sender: 'bot',
        text: selected.response,
        time: 'Just now'
      }]);
    }, 1200);
  };

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isTyping]);

  return (
    <div className="bg-grid-container">
      {/* Grid background & Orbs */}
      <div className="bg-grid-overlay"></div>
      <div className="glow-orb orb-primary"></div>
      <div className="glow-orb orb-secondary"></div>
      <div className="glow-orb orb-accent"></div>

      {/* Navigation Header */}
      <header className={`navbar ${mobileMenuOpen ? 'navbar-open' : ''}`}>
        <div className="container nav-container">
          <a href="#" className="logo-section">
            <img src="/app_icon.png" alt="nexARound Icon" style={{ width: '32px', height: '32px', borderRadius: '8px' }} />
            <span>nex<span className="text-teal">AR</span>ound</span>
          </a>
          
          <nav className="nav-links">
            <a href="#features" className="nav-link">Features</a>
            <a href="#neva" className="nav-link">AI Companion</a>
            <a href="#download" className="nav-link">Download</a>
          </nav>

          <div className="nav-actions">
            <a href="#download" className="btn btn-primary">
              <Smartphone size={16} />
              <span>Get the App</span>
            </a>
            <button 
              className="mobile-menu-btn" 
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              aria-label="Toggle Menu"
            >
              {mobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
            </button>
          </div>
        </div>

        {/* Mobile Navigation Dropdown */}
        <div className={`mobile-nav-menu ${mobileMenuOpen ? 'active' : ''}`}>
          <a href="#features" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>Features</a>
          <a href="#neva" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>AI Companion</a>
          <a href="#download" className="mobile-nav-link" onClick={() => setMobileMenuOpen(false)}>Download</a>
          <a href="#download" className="btn btn-primary mobile-menu-cta" onClick={() => setMobileMenuOpen(false)}>
            <Smartphone size={16} />
            <span>Get the App</span>
          </a>
        </div>
      </header>

      {/* Hero Section */}
      <section className="hero-section">
        <div className="container">
          <div className="hero-grid">
            <div className="hero-content">
              <div className="hero-badge">
                <Sparkles size={14} />
                <span>Next-Gen Smart Tourism</span>
              </div>
              <h1 className="hero-title">
                Explore the World with <span className="gradient-text-primary">Neva AI</span> & <span className="gradient-text-secondary">Live AR</span>
              </h1>
              <p className="hero-desc">
                nexARound is an AI-powered smart tourism companion. Real-time AR landmark identification, personalized routing, offline geospatial caching, and your own witty, stylish travel partner Neva, helping you discover hidden gems effortlessly.
              </p>
              <div className="hero-actions">
                <a href="#neva" className="btn btn-primary">
                  <span>Talk to Neva</span>
                  <ArrowRight size={16} />
                </a>
                <a href="#features" className="btn btn-secondary">
                  <span>Learn Features</span>
                </a>
              </div>
            </div>

            {/* Smart visual mobile mock */}
            <div className="hero-visual">
              {/* AR Radar Background Animation */}
              <div className="radar-scanner-container">
                <div className="radar-circle circle-1"></div>
                <div className="radar-circle circle-2"></div>
                <div className="radar-circle circle-3"></div>
                <div className="radar-sweep-line"></div>
                
                {/* Floating Coordinates */}
                <div className="coordinate-tag pos-1">LAT: 35.6895° N</div>
                <div className="coordinate-tag pos-2">LNG: 139.6917° E</div>
                <div className="coordinate-tag pos-3">ALT: 34m</div>
                <div className="coordinate-tag pos-4">SCANNING POS...</div>
              </div>

              <div className="mockup-wrapper animate-float">
                <div className="mockup-notch"></div>
                <div className="mockup-screen">
                  {/* Splash Screen View Only */}
                  <div style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    background: '#ffffff',
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    padding: '24px'
                  }}>
                    {/* Top left mini arrow/compass dot from screenshot */}
                    <div style={{ position: 'absolute', top: '16px', left: '16px', display: 'flex', alignItems: 'center' }}>
                      <div style={{
                        width: '18px',
                        height: '18px',
                        borderRadius: '50%',
                        background: '#007a7c',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        color: '#ffffff'
                      }}>
                        <Navigation size={8} style={{ transform: 'rotate(45deg)' }} />
                      </div>
                    </div>
                    
                    {/* Splash Logo Image */}
                    <img 
                      src="/app_logo.png" 
                      alt="nexARound Logo" 
                      style={{ 
                        width: '75%', 
                        height: 'auto',
                        marginBottom: '20px'
                      }} 
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Core Features Grid */}
      <section id="features" className="features-section">
        <div className="container">
          <div className="section-header">
            <h2 className="section-title">Revolutionizing the Travel Experience</h2>
            <p className="section-desc">
              nexARound bundles cutting edge spatial algorithms and Generative AI inside a beautiful, lightweight mobile app.
            </p>
          </div>

          <div className="features-grid">
            <div className="glass-card">
              <div className="feature-icon-wrapper bg-primary-gradient">
                <Bot size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Neva AI Companion</h3>
              <p className="feature-desc">
                Your witty, stylish travel partner available 24/7. Get context-aware insights, customizable itineraries, and local trivia styled with friendly emojis.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-secondary-gradient">
                <Map size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Live AR Identification</h3>
              <p className="feature-desc">
                Simply lift your camera in AR Mode. ML Kit and Gemini analyze your feed to overlay neon tags with directions, booking capabilities, and landmark history.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-accent-gradient">
                <Zap size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Geospatial Caching</h3>
              <p className="feature-desc">
                Custom Postgres GIS database combined with client-side Hive caches maps and details. Load locations instantly in under 50ms and save your phone battery.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-secondary-gradient">
                <Navigation size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Living Maps & Routing</h3>
              <p className="feature-desc">
                Integrates beautiful Google Maps and Mapbox routes. Seamlessly filters places by rating, category, and real-time open status.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-primary-gradient">
                <Globe size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Quick Integrations</h3>
              <p className="feature-desc">
                Direct actions from landmark cards: navigate via internal maps, check room availability on Booking.com, or summon an Uber with a single click.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Interactive Neva Chat Simulator */}
      <section id="neva" className="neva-section">
        <div className="container">
          <div className="neva-grid">
            <div className="neva-content">
              <div className="hero-badge">
                <Bot size={14} />
                <span>Live Interactive Chat</span>
              </div>
              <h2 className="section-title">Meet Neva: Your Smart Travel Partner</h2>
              <p className="section-desc" style={{ marginBottom: '24px' }}>
                Traditional guidebooks are static. Neva is alive, responding dynamically to your immediate physical surroundings, budget limits, and travel schedule.
              </p>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div style={{ display: 'flex', gap: '12px', alignItems: 'flex-start' }}>
                  <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(0, 122, 124, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: '3px' }}>
                    <Check size={14} color="#007a7c" />
                  </div>
                  <div>
                    <h4 style={{ fontSize: '16px', fontWeight: '600' }}>Context-Aware Suggestions</h4>
                    <p style={{ fontSize: '14px', color: 'var(--text-secondary)' }}>Neva knows where you are and details what to look out for.</p>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '12px', alignItems: 'flex-start' }}>
                  <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(0, 122, 124, 0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: '3px' }}>
                    <Check size={14} color="#007a7c" />
                  </div>
                  <div>
                    <h4 style={{ fontSize: '16px', fontWeight: '600' }}>Interactive Formatted Output</h4>
                    <p style={{ fontSize: '14px', color: 'var(--text-secondary)' }}>Answers are organized with headers, checklists, and highlights.</p>
                  </div>
                </div>
              </div>
            </div>

            {/* Chat Sim Box */}
            <div className="chat-simulator">
              <div className="chat-header">
                <div className="avatar" style={{ overflow: 'hidden' }}>
                  <img src="/neva_avatar.png" alt="Neva Avatar" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                </div>
                <div className="avatar-status">
                  <span className="avatar-name">Neva AI</span>
                  <span className="status-online">
                    <span className="status-dot"></span> Online
                  </span>
                </div>
              </div>

              {/* Chat messages stream */}
              <div className="chat-body">
                {messages.map((msg, index) => (
                  <div key={index} className={`message ${msg.sender === 'user' ? 'message-user' : 'message-bot'}`}>
                    <div 
                      className={msg.sender === 'user' ? 'message-bubble-user' : 'message-bubble-bot'}
                      dangerouslySetInnerHTML={{ __html: msg.text }}
                    />
                  </div>
                ))}

                {isTyping && (
                  <div className="message message-bot">
                    <div className="message-bubble-bot" style={{ display: 'flex', gap: '4px', padding: '12px 16px' }}>
                      <span className="typing-dot" style={{ animationDelay: '0s' }}></span>
                      <span className="typing-dot" style={{ animationDelay: '0.2s' }}></span>
                      <span className="typing-dot" style={{ animationDelay: '0.4s' }}></span>
                    </div>
                  </div>
                )}
                <div ref={chatEndRef} />
              </div>

              {/* Interactive choices footer */}
              <div className="chat-footer">
                <p style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '10px', fontWeight: '500' }}>
                  Select a topic to ask Neva:
                </p>
                <div className="prompt-suggestions">
                  <button onClick={() => handlePromptClick('itinerary')} className="prompt-chip">
                    Plan Tokyo Itinerary 🗼
                  </button>
                  <button onClick={() => handlePromptClick('ar')} className="prompt-chip">
                    How does AR work? 🕶️
                  </button>
                  <button onClick={() => handlePromptClick('cache')} className="prompt-chip">
                    Caching & Optimization ⚡
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Download Action Section */}
      <section id="download" className="cta-section">
        <div className="container">
          <div className="cta-box">
            <h2 className="cta-title">Start Your Companion Journey</h2>
            <p className="cta-desc">
              Download nexARound for your mobile device today to start exploring the world.
            </p>
            <div className="download-buttons">
              <a href="#" className="download-btn">
                <img src="/app_store.png" alt="App Store" style={{ width: '28px', height: '28px', objectFit: 'contain' }} />
                <div>
                  <span className="download-btn-sub">DOWNLOAD FOR</span>
                  <span className="download-btn-main">iOS App Store</span>
                </div>
              </a>
              <a href="#" className="download-btn">
                <img src="/play_store.png" alt="Google Play" style={{ width: '28px', height: '28px', objectFit: 'contain' }} />
                <div>
                  <span className="download-btn-sub">DOWNLOAD FOR</span>
                  <span className="download-btn-main">Google Play Store</span>
                </div>
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="footer">
        <div className="container footer-container">
          <div className="footer-brand">
            <img src="/app_icon.png" alt="nexARound Icon" style={{ width: '24px', height: '24px', borderRadius: '6px' }} />
            <span>nex<span className="text-teal">AR</span>ound</span>
          </div>
          <p>© {new Date().getFullYear()} nexARound Smart Tourism. All rights reserved.</p>
          <div className="footer-links">
            <a href="#features" className="footer-link">Features</a>
            <a href="#neva" className="footer-link">AI Companion</a>
            <a href="#download" className="footer-link">Download</a>
          </div>
        </div>
      </footer>

      {/* Embedded CSS for simulator animation details */}
      <style>{`
        .bg-grid-container {
          position: relative;
          min-height: 100vh;
        }
        .typing-dot {
          width: 6px;
          height: 6px;
          background: var(--text-secondary);
          border-radius: 50%;
          display: inline-block;
          animation: dot-blink 1.4s infinite both;
        }
        @keyframes dot-blink {
          0% { opacity: 0.2; transform: scale(0.8); }
          20% { opacity: 1; transform: scale(1.1); }
          100% { opacity: 0.2; transform: scale(0.8); }
        }
      `}</style>
    </div>
  );
}
