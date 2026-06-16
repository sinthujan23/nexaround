import React, { useState, useRef, useEffect } from 'react';
import { 
  Compass, 
  Sparkles, 
  Map, 
  Navigation, 
  Server, 
  Check, 
  Smartphone, 
  ArrowRight, 
  ExternalLink, 
  Bot, 
  Send, 
  Globe, 
  Shield, 
  Zap, 
  MapPin,
  TrendingUp,
  Cpu
} from 'lucide-react';

export default function App() {
  const [activeTab, setActiveTab] = useState('neva');
  
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
      <header className="navbar">
        <div className="container nav-container">
          <a href="#" className="logo-section">
            <Compass className="animate-float" size={28} color="#ec4899" />
            <span>NexAround</span>
          </a>
          
          <nav className="nav-links">
            <a href="#features" className="nav-link">Features</a>
            <a href="#neva" className="nav-link">AI Companion</a>
            <a href="#download" className="nav-link">Download</a>
            <a href="https://admin.nexaround.com" target="_blank" rel="noopener noreferrer" className="nav-link flex items-center gap-1">
              Admin <ExternalLink size={14} className="inline" />
            </a>
          </nav>

          <div className="nav-actions">
            <a href="#download" className="btn btn-primary">
              <Smartphone size={16} />
              <span>Get the App</span>
            </a>
          </div>
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
                Explore the World with <span className="gradient-text-pink">Neva AI</span> & <span className="gradient-text-cyan">Live AR</span>
              </h1>
              <p className="hero-desc">
                NexAround is an AI-powered smart tourism companion. Real-time AR landmark identification, personalized routing, offline geospatial caching, and your own witty, stylish travel partner Neva, helping you discover hidden gems effortlessly.
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
              <div className="mockup-wrapper animate-float">
                <div className="mockup-notch"></div>
                <div className="mockup-screen">
                  {/* Mock Phone App Header */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px', marginTop: '16px', padding: '0 4px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Compass size={18} color="#a855f7" />
                      <span style={{ fontSize: '12px', fontWeight: '800', color: '#fff' }}>NexAround</span>
                    </div>
                    <span style={{ fontSize: '10px', color: '#10b981', background: 'rgba(16, 185, 129, 0.15)', padding: '2px 6px', borderRadius: '999px', fontWeight: '600' }}>GPS Active</span>
                  </div>

                  {/* Mock Map / AR Card Screen */}
                  <div style={{ flex: 1, borderRadius: '16px', overflow: 'hidden', background: '#1e293b', border: '1px solid rgba(255, 255, 255, 0.05)', position: 'relative', display: 'flex', flexDirection: 'column', gap: '8px', padding: '8px' }}>
                    {/* Simulated AR Camera Stream with floating tag */}
                    <div style={{ height: '48%', background: 'linear-gradient(rgba(0, 0, 0, 0.1), rgba(0, 0, 0, 0.6)), url("https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=300&auto=format&fit=crop&q=60") center/cover', borderRadius: '12px', display: 'flex', alignItems: 'flex-end', padding: '8px', position: 'relative' }}>
                      <div style={{ position: 'absolute', top: '8px', left: '8px', padding: '4px 8px', borderRadius: '6px', background: 'rgba(0,0,0,0.6)', fontSize: '9px', fontWeight: '700', color: '#06b6d4', display: 'flex', alignItems: 'center', gap: '3px' }}>
                        <span style={{ width: '4px', height: '4px', background: '#06b6d4', borderRadius: '50%' }}></span> AR MODE
                      </div>
                      
                      {/* Interactive Tag */}
                      <div style={{ background: 'rgba(15, 23, 42, 0.85)', backdropFilter: 'blur(4px)', border: '1px solid #a855f7', borderRadius: '8px', padding: '6px 10px', width: '100%', display: 'flex', justifyContent: 'space-between', alignItems: 'center', boxShadow: '0 4px 12px rgba(168, 85, 247, 0.3)' }}>
                        <div>
                          <div style={{ fontSize: '10px', fontWeight: '700', color: '#fff' }}>Senso-ji Temple</div>
                          <div style={{ fontSize: '8px', color: '#a855f7' }}>Landmark • Asakusa</div>
                        </div>
                        <Check size={12} color="#a855f7" />
                      </div>
                    </div>

                    {/* Discovery recommendation Card */}
                    <div style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.05)', borderRadius: '12px', padding: '10px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span style={{ fontSize: '10px', fontWeight: '700', color: '#f3f4f6' }}>Neva's Hotspots</span>
                        <span style={{ fontSize: '9px', color: '#a855f7', fontWeight: '600' }}>98% Match</span>
                      </div>
                      <div style={{ fontSize: '9px', color: '#9ca3af', lineHeight: '1.4' }}>
                        Based on your profile, I recommend visiting <strong>Shibuya Sky</strong> at 5:30 PM for sunset.
                      </div>
                      <div style={{ display: 'flex', gap: '4px', marginTop: '2px' }}>
                        <span style={{ fontSize: '8px', background: 'rgba(255,255,255,0.05)', padding: '2px 6px', borderRadius: '4px', color: '#d1d5db' }}>#sunset</span>
                        <span style={{ fontSize: '8px', background: 'rgba(255,255,255,0.05)', padding: '2px 6px', borderRadius: '4px', color: '#d1d5db' }}>#views</span>
                      </div>
                    </div>

                    {/* Navigation Mini Map Panel */}
                    <div style={{ background: 'rgba(6, 182, 212, 0.05)', border: '1px solid rgba(6, 182, 212, 0.1)', borderRadius: '12px', padding: '8px', display: 'flex', alignItems: 'center', gap: '8px', marginTop: 'auto' }}>
                      <div style={{ width: '28px', height: '28px', background: 'var(--gradient-secondary)', borderRadius: '8px', display: 'flex', alignItems: 'center', justifySelf: 'center', justifyContent: 'center' }}>
                        <Navigation size={14} color="#fff" />
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontSize: '9px', fontWeight: '700', color: '#fff' }}>Route Optimization</div>
                        <div style={{ fontSize: '8px', color: '#9ca3af' }}>3 mins walk to next location</div>
                      </div>
                    </div>
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
              NexAround bundles cutting edge spatial algorithms and Generative AI inside a beautiful, lightweight mobile app.
            </p>
          </div>

          <div className="features-grid">
            <div className="glass-card">
              <div className="feature-icon-wrapper bg-purple-gradient">
                <Bot size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Neva AI Companion</h3>
              <p className="feature-desc">
                Your witty, stylish travel partner available 24/7. Get context-aware insights, customizable itineraries, and local trivia styled with friendly emojis.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-cyan-gradient">
                <Map size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Live AR Identification</h3>
              <p className="feature-desc">
                Simply lift your camera in AR Mode. ML Kit and Gemini analyze your feed to overlay neon tags with directions, booking capabilities, and landmark history.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-amber-gradient">
                <Zap size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Geospatial Caching</h3>
              <p className="feature-desc">
                Custom Postgres GIS database combined with client-side Hive caches maps and details. Load locations instantly in under 50ms and save your phone battery.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-cyan-gradient">
                <Navigation size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Living Maps & Routing</h3>
              <p className="feature-desc">
                Integrates beautiful Google Maps and Mapbox routes. Seamlessly filters places by rating, category, and real-time open status.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-purple-gradient">
                <Globe size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Quick Integrations</h3>
              <p className="feature-desc">
                Direct actions from landmark cards: navigate via internal maps, check room availability on Booking.com, or summon an Uber with a single click.
              </p>
            </div>

            <div className="glass-card">
              <div className="feature-icon-wrapper bg-amber-gradient">
                <Shield size={24} color="#fff" />
              </div>
              <h3 className="feature-title">Admin Dashboard</h3>
              <p className="feature-desc">
                Manage accounts, pending location approvals, payments, security keys, and engagement reports with our robust React + Vite administration system.
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
                  <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(6,182,212,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: '3px' }}>
                    <Check size={14} color="#06b6d4" />
                  </div>
                  <div>
                    <h4 style={{ fontSize: '16px', fontWeight: '600' }}>Context-Aware Suggestions</h4>
                    <p style={{ fontSize: '14px', color: 'var(--text-secondary)' }}>Neva knows where you are and details what to look out for.</p>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '12px', alignItems: 'flex-start' }}>
                  <div style={{ width: '24px', height: '24px', borderRadius: '50%', background: 'rgba(168,85,247,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: '3px' }}>
                    <Check size={14} color="#a855f7" />
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
                <div className="avatar">N</div>
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
              Download NexAround for your mobile device today, or access the admin panel to manage points of interest.
            </p>
            <div className="download-buttons">
              <a href="#" className="download-btn">
                <Smartphone size={24} color="#a855f7" />
                <div>
                  <span className="download-btn-sub">Download for</span>
                  <span className="download-btn-main">iOS App Store</span>
                </div>
              </a>
              <a href="#" className="download-btn">
                <Smartphone size={24} color="#06b6d4" />
                <div>
                  <span className="download-btn-sub">Download for</span>
                  <span className="download-btn-main">Google Play Store</span>
                </div>
              </a>
              <a href="https://admin.nexaround.com" target="_blank" rel="noopener noreferrer" className="download-btn" style={{ borderColor: 'rgba(168, 85, 247, 0.3)' }}>
                <Server size={24} color="#ec4899" />
                <div>
                  <span className="download-btn-sub">Control Center</span>
                  <span className="download-btn-main">Admin Dashboard</span>
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
            <Compass size={20} color="#ec4899" />
            <span>NexAround</span>
          </div>
          <p>© {new Date().getFullYear()} NexAround Smart Tourism. All rights reserved.</p>
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
