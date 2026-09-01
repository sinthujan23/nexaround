import { useState, useEffect } from 'react';
import { 
  Camera, Compass, MessageSquare, MapPin, Landmark, 
  Ticket, Globe, ShieldCheck, Zap, Layers, Sparkles, 
  CheckCircle2, ArrowRight, Smartphone, ChevronRight,
  Headphones, Navigation, Utensils, Cpu, HeartHandshake
} from 'lucide-react';
import { NavLink } from 'react-router-dom';
import StoreButtons from '../components/StoreButtons';

const heroBackgrounds = [
  '/bg_eiffel_tower.png',
  '/bg_colosseum_rome.png',
  '/bg_sigiriya.png',
  '/bg_pyramids_giza.png',
  '/bg_taj_mahal.png',
  '/bg_machu_picchu.png',
  '/bg_great_wall.png',
  '/bg_sydney_opera.png',
  '/bg_statue_liberty.png',
];

export default function Services() {
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);
  const platformServices = [
    {
      num: '01',
      icon: <Camera style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Spatial AR Camera Landmark Vision',
      desc: 'Edge-accelerated computer vision that identifies ancient temples, heritage ruins, city landmarks, and museum artwork in sub-500ms.',
      highlights: [
        'Real-time camera landmark recognition',
        'Interactive 3D historical & structural overlays',
        'Spatial vantage point contextual storytelling'
      ]
    },
    {
      num: '02',
      icon: <Compass style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Odyssey AI Dynamic Itinerary Engine',
      desc: 'Multi-day personalized travel planner that optimizes routes, adapts to weather, and balances pacing across your preferred budget tier.',
      highlights: [
        'Dynamic multi-day route & transit optimization',
        'Budget matching from backpacker to luxury',
        'Live opening hours & crowd density sync'
      ]
    },
    {
      num: '03',
      icon: <MessageSquare style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Neva 24/7 AI Smart Concierge',
      desc: 'Context-aware conversational companion delivering instant local recommendations, phrasebook guidance, and emergency safety support.',
      highlights: [
        'Natural conversational voice & text intelligence',
        'Hyper-local dining & dietary preference filters',
        'Real-time itinerary adjustments on the fly'
      ]
    },
    {
      num: '04',
      icon: <MapPin style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Living Tourism Radar & Proximity Maps',
      desc: 'Intelligent spatial radar scanning attractions, viewpoints, authentic street food, and verified healthcare facilities in your immediate radius.',
      highlights: [
        'Live proximity distance radar around your GPS',
        'Curated Food, Nature, and Cultural POI filters',
        'Direct skip-the-line ticket bookings'
      ]
    },
    {
      num: '05',
      icon: <Landmark style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Curated Museum & Heritage Guides',
      desc: 'Interactive exhibit walkthroughs crafted by historians and cultural experts with room-by-room indoor floorplan navigation.',
      highlights: [
        'Deep historical storytelling for world wonders',
        'Room-by-room gallery & exhibit walkthroughs',
        'Must-see masterworks & verified schedules'
      ]
    },
    {
      num: '06',
      icon: <Ticket style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Integrated Bookings & Transit Dispatch',
      desc: 'Book verified activities, museum tickets, hotels, and Uber rides directly inside your daily itinerary without jumping between multiple apps.',
      highlights: [
        'Integrated with Viator, GetYourGuide, Headout',
        'One-tap Uber & local ride-hailing dispatch',
        'Zero markups on official landmark tickets'
      ]
    }
  ];

  const enterpriseServices = [
    {
      icon: <Landmark style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Heritage & Landmark 3D Digitization',
      tag: 'For Cultural Ministries & DMOs',
      desc: 'We create photogrammetric 3D spatial models and historical reconstruction overlays for national heritage sites.'
    },
    {
      icon: <Globe style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Destination Tourism Telemetry',
      tag: 'For Smart Cities & Tourism Boards',
      desc: 'Anonymized visitor flow analytics, dwell time tracking, and crowd distribution heatmaps for sustainable destination management.'
    },
    {
      icon: <Landmark style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Curated Museum Exhibit Guide Production',
      tag: 'For Museums & Heritage Sites',
      desc: 'End-to-end research, multilingual exhibit descriptions, and gallery curation for permanent exhibitions and galleries.'
    },
    {
      icon: <HeartHandshake style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Hospitality Partner White-Labeling',
      tag: 'For Resorts & Luxury Hotels',
      desc: 'Customized in-stay guest concierges featuring branded hotel recommendations, wellness schedules, and VIP excursions.'
    }
  ];

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '100px' }}>
      
      {/* ═══════════════════════════════════════════════════════ */}
      {/* ═══ HERO SECTION (EXACT MATCHING HOME PAGE LAYOUT & SIZE - 100VH) ═══ */}
      <section className="hero-section" style={{ 
        position: 'relative', 
        background: '#080a14', 
        overflow: 'hidden'
      }}>
        
        {/* Smooth Auto-Rotating Background Images with Cross-Fade */}
        {heroBackgrounds.map((bg, idx) => (
          <div
            key={bg}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              backgroundImage: `url(${bg})`,
              backgroundSize: 'cover',
              backgroundPosition: 'center 40%',
              opacity: idx === currentBgIndex ? 0.55 : 0,
              filter: 'brightness(1.1) contrast(1.05)',
              transform: idx === currentBgIndex ? 'scale(1.03)' : 'scale(1)',
              transition: 'opacity 1.4s ease-in-out, transform 5s ease-out',
              zIndex: 1,
              pointerEvents: 'none'
            }}
          />
        ))}

        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(90deg, rgba(8, 10, 20, 0.88) 0%, rgba(8, 10, 20, 0.55) 45%, rgba(8, 10, 20, 0.15) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(180deg, transparent 40%, rgba(8, 10, 20, 0.4) 75%, rgba(8, 10, 20, 0.98) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        {/* Hero Content (Left-Aligned, Clean Typography Matching Home) */}
        <div className="container" style={{ position: 'relative', zIndex: 3 }}>
          <div style={{ maxWidth: '820px', textAlign: 'left' }}>
            
            {/* Main Headline */}
            <h1 style={{ 
              fontSize: 'clamp(2.8rem, 6vw, 4.6rem)', 
              fontWeight: 300, 
              color: '#ffffff', 
              lineHeight: 1.15, 
              letterSpacing: '-0.03em', 
              margin: '0 0 20px',
              textShadow: '0 2px 14px rgba(0,0,0,0.5)'
            }}>
              Next-Gen Services for <span style={{ fontWeight: 500, color: '#00d2d3' }}>Modern Tourism</span>.
            </h1>

            {/* Sub-Headline */}
            <p style={{ 
              fontSize: 'clamp(1.05rem, 1.8vw, 1.22rem)', 
              color: 'rgba(255, 255, 255, 0.88)', 
              lineHeight: 1.65, 
              margin: '0 0 38px', 
              maxWidth: '660px',
              fontWeight: 300,
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              Explore the advanced spatial AI, computer vision, dynamic itinerary engines, and heritage exhibit services that make NexAround the ultimate smart tourism companion.
            </p>

            {/* Action Buttons */}
            <div className="hero-btn-group" style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
              <a 
                href="#services-grid" 
                onClick={(e) => { 
                  e.preventDefault(); 
                  document.getElementById('services-grid')?.scrollIntoView({ behavior: 'smooth' }); 
                }} 
                style={{ 
                  background: '#ffffff', 
                  color: '#000000', 
                  padding: '14px 28px', 
                  borderRadius: '9999px', 
                  fontSize: '15px', 
                  fontWeight: 500, 
                  display: 'inline-flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  textDecoration: 'none',
                  boxShadow: '0 4px 20px rgba(0,0,0,0.25)',
                  transition: 'all 0.25s ease'
                }}
                onMouseEnter={(e) => { e.currentTarget.style.transform = 'translateY(-2px)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.transform = 'translateY(0)'; }}
              >
                <span>Explore App Services</span>
                <ChevronRight style={{ width: '16px', height: '16px' }} />
              </a>
              <NavLink 
                to="/app" 
                style={{ 
                  background: 'rgba(255, 255, 255, 0.08)', 
                  color: '#ffffff', 
                  border: '1.5px solid rgba(255, 255, 255, 0.45)', 
                  padding: '14px 28px', 
                  borderRadius: '9999px', 
                  fontSize: '15px', 
                  fontWeight: 500, 
                  display: 'inline-flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  textDecoration: 'none',
                  backdropFilter: 'blur(8px)',
                  WebkitBackdropFilter: 'blur(8px)',
                  transition: 'all 0.25s ease'
                }}
                onMouseEnter={(e) => { 
                  e.currentTarget.style.background = 'rgba(255, 255, 255, 0.18)'; 
                  e.currentTarget.style.transform = 'translateY(-2px)'; 
                }}
                onMouseLeave={(e) => { 
                  e.currentTarget.style.background = 'rgba(255, 255, 255, 0.08)'; 
                  e.currentTarget.style.transform = 'translateY(0)'; 
                }}
              >
                <span>View App Modules</span>
              </NavLink>
            </div>
          </div>
        </div>
      </section>

      {/* ═══ 6 CORE APP SERVICES GRID ═══ */}
      <section id="services-grid" className="section-padding" style={{ background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '720px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>App Capabilities</div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              Intelligent Services for <span className="text-gradient-teal">Effortless Travel</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.7 }}>
              Every service is built into the NexAround mobile application to guide your journey from curiosity to unforgettable memories.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-3">
            {platformServices.map((s, i) => (
              <div key={i} className="feature-card" style={{ textAlign: 'left', padding: '36px 30px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px' }}>
                  <span style={{ fontSize: '1.8rem', fontWeight: 500, color: 'rgba(0, 122, 124, 0.2)', fontFamily: 'var(--font-mono)' }}>{s.num}</span>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.2)' }}>
                    {s.icon}
                  </div>
                </div>

                <h3 style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px', lineHeight: 1.25 }}>
                  {s.title}
                </h3>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 20px' }}>
                  {s.desc}
                </p>

                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', paddingTop: '16px', borderTop: '1px solid var(--border-color)' }}>
                  {s.highlights.map((h, idx) => (
                    <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.86rem', color: 'var(--dark-charcoal)', fontWeight: 500 }}>
                      <CheckCircle2 style={{ width: '14px', height: '14px', color: 'var(--brand-teal)', flexShrink: 0 }} />
                      <span>{h}</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ ENTERPRISE & PARTNERSHIP SERVICES ═══ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)', borderTop: '1px solid var(--border-color)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '720px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>B2B & Partner Solutions</div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              Services for <span className="text-gradient-teal">Destinations & Tourism Partners</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.7 }}>
              Collaborate with NexAround to bring cutting-edge spatial storytelling and digital concierge capabilities to your destination.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '24px' }} className="grid-4">
            {enterpriseServices.map((m, i) => (
              <div key={i} className="feature-card" style={{ padding: '32px 24px', textAlign: 'left' }}>
                <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '20px', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  {m.icon}
                </div>
                <span style={{ fontSize: '0.74rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '0.8px' }}>{m.tag}</span>
                <h3 style={{ fontSize: '1.2rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '4px 0 12px' }}>{m.title}</h3>
                <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>{m.desc}</p>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ CTA SECTION ═══ */}
      <section className="container" style={{ padding: '60px 32px 0' }}>
        <div style={{ 
          padding: '60px 44px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)', 
          border: '1px solid rgba(0, 122, 124, 0.25)',
          borderRadius: 'var(--radius-xl)',
          maxWidth: '960px',
          margin: '0 auto',
          boxShadow: '0 20px 50px -10px rgba(0, 122, 124, 0.1)'
        }}>
          <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
            <Zap style={{ width: '14px', height: '14px' }} /> Discover What's Next Around You
          </div>

          <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
            Elevate Your Travel with Spatial AI
          </h2>

          <p style={{ color: 'var(--text-secondary)', margin: '0 auto 36px', fontSize: '1.08rem', maxWidth: '620px', lineHeight: 1.7 }}>
            Download the NexAround mobile app today and experience the world with real-time AR recognition, smart Odyssey itineraries, and Neva 24/7 AI.
          </p>

          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/get-app" className="btn-teal" style={{ padding: '16px 36px', fontSize: '1rem', textDecoration: 'none' }}>
              <Smartphone style={{ width: '18px', height: '18px' }} />
              <span>Get the NexAround App</span>
              <ArrowRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}

