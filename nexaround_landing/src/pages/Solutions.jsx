import { useState, useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import { 
  Sparkles, Camera, Compass, MessageSquare, MapPin, 
  Landmark, Globe, BookOpen, ArrowRight, CheckCircle2, 
  Smartphone, ShieldCheck, Zap, Star, ChevronRight,
  Users, Building2, Hotel, Ticket, Plane, Eye, Layers
} from 'lucide-react';
import StoreButtons from '../components/StoreButtons';

const heroBackgrounds = [
  '/bg_sigiriya.png',
  '/bg_colosseum_rome.png',
  '/bg_eiffel_tower.png',
  '/bg_pyramids_giza.png',
  '/bg_taj_mahal.png',
  '/bg_machu_picchu.png',
  '/bg_great_wall.png',
  '/bg_sydney_opera.png',
  '/bg_statue_liberty.png',
];

export default function Solutions() {
  const [activeAudience, setActiveAudience] = useState('travelers');
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);

  const solutions = [
    {
      id: 'travelers',
      badge: 'B2C Travel Companion',
      tag: 'For Global Travelers & Explorers',
      title: 'Intelligent Spatial Travel in Your Pocket',
      subtitle: 'From itinerary planning to real-world AR exploration and memory journaling',
      desc: 'NexAround transforms the traveler journey from overwhelming research into seamless discovery. Point your camera at any monument, ask Neva anything in your native language, and let Odyssey curate the perfect day.',
      icon: <Compass style={{ width: '26px', height: '26px', color: 'var(--brand-teal)' }} />,
      image: '/app_scan_landmark_v4.png',
      features: [
        'Sub-second real-time camera AR landmark scanning',
        'Odyssey AI smart multi-day itinerary generation',
        'Neva 24/7 multilingual conversational travel assistant',
        'Living radar map for authentic food, viewpoints & cafes',
        'Automatic GPS landmark passport stamps & photo journal'
      ]
    },
    {
      id: 'dmo',
      badge: 'Tourism Boards & Heritage',
      tag: 'For DMOs & Cultural Ministries',
      title: 'Smart Heritage Digitization & Visitor Telemetry',
      subtitle: 'Transform historical monuments into interactive spatial learning centers',
      desc: 'Empower national tourism organizations and cultural ministries to digitize historic monuments, preserve cultural heritage with interactive AR overlays, and understand visitor flow patterns without invasive hardware.',
      icon: <Landmark style={{ width: '26px', height: '26px', color: 'var(--brand-teal)' }} />,
      image: '/app_heritage_dmo_v4.png',
      features: [
        'Interactive historical & architectural AR overlays',
        'Interactive digital exhibit guide preservation',
        'Visitor footfall telemetry & crowd distribution insights',
        'Zero-hardware maintenance: runs natively on traveler smartphones',
        'Eco-friendly digital-only guides replacing paper brochures'
      ]
    },
    {
      id: 'museums',
      badge: 'Museums & Galleries',
      tag: 'For Cultural Institutions & Ruins',
      title: 'Next-Gen Interactive Museum & Exhibit Guides',
      subtitle: 'Expert exhibit walkthroughs & computer vision art recognition',
      desc: 'Replace static paper brochures and outdated wands with rich, interactive smartphone guides. Visitors point their camera at paintings, statues, or ancient ruins to discover spatial storytelling, artist biographies, and exhibit floorplans.',
      icon: <BookOpen style={{ width: '26px', height: '26px', color: 'var(--brand-teal)' }} />,
      image: '/app_cap_02_v4.png',
      features: [
        'Camera vision painting & artifact recognition',
        'Interactive exhibit descriptions with curated historian notes',
        'Interactive room-by-room gallery floorplan navigation',
        'Rich exhibit descriptions with verified historian insights',
        'Curated expert commentary from historians and curators'
      ]
    },
    {
      id: 'hospitality',
      badge: 'Hotels & Tour Operators',
      tag: 'For Hospitality & Travel Providers',
      title: 'In-Stay Concierge & Experience Monetization',
      subtitle: 'Elevate guest stays with hyper-local AI recommendations and bookings',
      desc: 'Hotels, resorts, and tour operators can deliver instant local recommendations to their guests. Seamlessly connect guests with verified local dining, skip-the-line activities, and integrated transit.',
      icon: <Hotel style={{ width: '26px', height: '26px', color: 'var(--brand-teal)' }} />,
      image: '/app_download_v4.png',
      features: [
        'Curated neighborhood guides verified by local experts',
        'Direct ticket & experience integration with top networks',
        'Seamless taxi & transit dispatch directly in the itinerary',
        'Real-time opening status & dietary safety recommendations',
        'Enhanced guest satisfaction and in-destination spend'
      ]
    }
  ];

  const benefits = [
    {
      title: 'Zero Hardware Required',
      desc: 'No rented hardware wands or beacons needed. The entire spatial experience runs on consumer smartphones.',
      icon: <Smartphone style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />
    },
    {
      title: 'Live Spatial Telemetry',
      desc: 'Real-time camera landmark recognition and live GPS radar around your destination.',
      icon: <ShieldCheck style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />
    },
    {
      title: 'Ecosystem Integrations',
      desc: 'Direct integrations with Viator, GetYourGuide, Headout, and Uber for seamless booking execution.',
      icon: <Ticket style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />
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
              Transforming Tourism with <span style={{ fontWeight: 500, color: '#00d2d3' }}>Spatial AI</span>.
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
              Discover how NexAround solves critical challenges for modern travelers, heritage landmarks, museums, and destination tourism boards worldwide.
            </p>

            {/* Action Buttons */}
            <div className="hero-btn-group" style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
              <a 
                href="#audiences" 
                onClick={(e) => { 
                  e.preventDefault(); 
                  document.getElementById('audiences')?.scrollIntoView({ behavior: 'smooth' }); 
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
                <span>Explore Solutions</span>
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
                <span>View App Features</span>
              </NavLink>
            </div>
          </div>
        </div>
      </section>

      {/* ═══ AUDIENCE TAB SELECTOR ═══ */}
      <section id="audiences" className="section-padding" style={{ background: 'var(--bg-light)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '720px', margin: '0 auto 52px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '14px' }}>
              <Users style={{ width: '14px', height: '14px' }} /> Tailored Solutions
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 14px', letterSpacing: '-0.025em' }}>
              Solutions Built for the <span className="text-gradient-teal">Entire Tourism Ecosystem</span>
            </h2>
            <p style={{ fontSize: '1.05rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              Select a sector below to explore how NexAround elevates discovery, heritage preservation, and visitor engagement.
            </p>
          </div>

          {/* Horizontal Tab Switcher */}
          <div style={{ 
            display: 'flex', 
            gap: '12px', 
            justifyContent: 'center', 
            flexWrap: 'wrap', 
            marginBottom: '44px' 
          }}>
            {[
              { id: 'travelers', label: 'For Travelers & Explorers', num: '01' },
              { id: 'dmo', label: 'For Tourism Boards & Heritage', num: '02' },
              { id: 'museums', label: 'For Museums & Cultural Sites', num: '03' },
              { id: 'hospitality', label: 'For Hotels & Tour Operators', num: '04' },
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveAudience(tab.id)}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '10px',
                  padding: '14px 24px',
                  borderRadius: '9999px',
                  background: activeAudience === tab.id ? 'var(--brand-teal)' : '#ffffff',
                  color: activeAudience === tab.id ? '#ffffff' : 'var(--dark-charcoal)',
                  border: activeAudience === tab.id ? '1px solid var(--brand-teal)' : '1px solid var(--border-color)',
                  cursor: 'pointer',
                  fontWeight: 500,
                  fontSize: '0.92rem',
                  transition: 'all 0.25s ease',
                  boxShadow: activeAudience === tab.id ? 'var(--shadow-teal)' : 'var(--shadow-sm)'
                }}
              >
                <span style={{
                  width: '24px',
                  height: '24px',
                  borderRadius: '50%',
                  background: activeAudience === tab.id ? '#ffffff' : 'var(--bg-surface)',
                  color: activeAudience === tab.id ? 'var(--brand-teal)' : 'var(--text-muted)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: '0.75rem',
                  fontWeight: 500
                }}>
                  {tab.num}
                </span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>

          {/* Active Solution Card */}
          {solutions.filter(s => s.id === activeAudience).map((sol) => (
            <div 
              key={sol.id} 
              className="feature-card" 
              style={{ 
                padding: '52px 48px', 
                border: '1px solid rgba(0, 122, 124, 0.25)',
                background: '#ffffff'
              }}
            >
              <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '52px', alignItems: 'center' }} className="grid-2">
                
                <div style={{ textAlign: 'left' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
                    <div style={{ width: '52px', height: '52px', borderRadius: '16px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                      {sol.icon}
                    </div>
                    <span style={{ fontSize: '0.78rem', fontWeight: 500, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.08)', padding: '6px 14px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.8px' }}>
                      {sol.badge} • {sol.tag}
                    </span>
                  </div>

                  <h3 style={{ fontSize: 'clamp(1.9rem, 3.2vw, 2.5rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 10px', lineHeight: 1.2 }}>
                    {sol.title}
                  </h3>

                  <div style={{ fontSize: '1.05rem', fontWeight: 500, color: 'var(--brand-teal)', marginBottom: '18px' }}>
                    {sol.subtitle}
                  </div>

                  <p style={{ fontSize: '1.02rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 28px' }}>
                    {sol.desc}
                  </p>

                  <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginBottom: '32px', paddingTop: '16px', borderTop: '1px solid var(--border-color)' }}>
                    {sol.features.map((feat, idx) => (
                      <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 500 }}>
                        <CheckCircle2 style={{ width: '16px', height: '16px', color: 'var(--brand-teal)', flexShrink: 0 }} />
                        <span>{feat}</span>
                      </div>
                    ))}
                  </div>

                  <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
                    <NavLink to="/app" className="btn-teal">
                      <span>Explore App Features</span>
                      <ArrowRight style={{ width: '16px', height: '16px' }} />
                    </NavLink>
                    <NavLink to="/get-app" className="btn-secondary">
                      <span>Get the App</span>
                    </NavLink>
                  </div>
                </div>

                <div style={{ display: 'flex', justifyContent: 'center' }}>
                  <div style={{
                    maxWidth: '320px',
                    width: '100%',
                    borderRadius: '28px',
                    overflow: 'hidden',
                    boxShadow: '0 25px 60px rgba(10, 17, 24, 0.22)',
                    border: '6px solid #111a24',
                    background: '#111a24'
                  }}>
                    <img src={sol.image} alt={sol.title} style={{ width: '100%', height: 'auto', display: 'block' }} />
                  </div>
                </div>

              </div>
            </div>
          ))}

        </div>
      </section>

      {/* ═══ PLATFORM ADVANTAGES GRID ═══ */}
      <section className="section-padding" style={{ background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '700px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '14px' }}>
              <Zap style={{ width: '14px', height: '14px' }} /> Core Value
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              Why Choose the <span className="text-gradient-teal">NexAround Ecosystem</span>
            </h2>
            <p style={{ fontSize: '1.05rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              Engineered for seamless digital travel without physical bottlenecks or hardware friction.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-3">
            {benefits.map((b, idx) => (
              <div key={idx} className="feature-card" style={{ padding: '36px 26px', textAlign: 'left' }}>
                <div style={{ width: '52px', height: '52px', borderRadius: '14px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '20px', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  {b.icon}
                </div>
                <h3 style={{ fontSize: '1.2rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 10px' }}>
                  {b.title}
                </h3>
                <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                  {b.desc}
                </p>
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
            <Zap style={{ width: '14px', height: '14px' }} /> Transform Your Destination
          </div>

          <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
            Ready to Experience the NexAround Platform?
          </h2>

          <p style={{ color: 'var(--text-secondary)', margin: '0 auto 36px', fontSize: '1.08rem', maxWidth: '620px', lineHeight: 1.7 }}>
            Download the consumer app or partner with us to deploy spatial guides across your landmarks, museums, and hotels.
          </p>

          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/get-app" className="btn-teal" style={{ padding: '16px 36px', fontSize: '1rem', textDecoration: 'none' }}>
              <Smartphone style={{ width: '18px', height: '18px' }} />
              <span>Get the App</span>
              <ArrowRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
            <NavLink to="/contact" className="btn-secondary" style={{ padding: '16px 28px', fontSize: '1rem', textDecoration: 'none' }}>
              <span>Partner With Us</span>
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
