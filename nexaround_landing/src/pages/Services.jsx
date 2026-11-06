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
      title: 'AR Discovery',
      desc: 'Hold up your phone to see nearby places over the camera view. Point at a place and nexARound uses your location and compass to show what it is.',
      highlights: [
        'Place labels by category',
        'Ask Neva about the place in front of you',
        'Walking routes in the camera view'
      ]
    },
    {
      num: '02',
      icon: <Compass style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Odyssey AI Trip Planner',
      desc: 'A complete day-by-day trip plan from your destination, dates, travellers and budget, with flights, stays and visa guidance.',
      highlights: [
        'Routes across several cities',
        'Budget breakdown line by line',
        'What to book now and what can wait'
      ]
    },
    {
      num: '03',
      icon: <MessageSquare style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Neva AI Companion',
      desc: 'Chat or talk with Neva about places, food, history and what to do next, with answers based on your location.',
      highlights: [
        'Text and voice chat',
        'Suggested places shown on a map',
        'Shortcuts to the right tool'
      ]
    },
    {
      num: '04',
      icon: <Landmark style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'City Guides & Museum Guides',
      desc: 'Day-by-day city guides with live navigation, and route guides to more than 50 leading museums.',
      highlights: [
        'Plan by day or by place',
        'Public transport directions',
        'Museum routes from 3 hours to 2 days'
      ]
    },
    {
      num: '05',
      icon: <MapPin style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Smart Maps & Discover',
      desc: 'A 3D map with turn-by-turn navigation, and nearby places by category, from food and nature to hospitals.',
      highlights: [
        'Driving and walking directions',
        'Auto Tour of the top places',
        'Local emergency numbers and phrases'
      ]
    },
    {
      num: '06',
      icon: <Ticket style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Local Experiences & Booking Partners',
      desc: 'Request dates for experiences run by local providers, and book flights, stays, tours and more on trusted partner sites.',
      highlights: [
        'The provider confirms your date',
        'Pay the provider at the experience',
        'Links for flights, stays, eSIMs and insurance'
      ]
    }
  ];

  const enterpriseServices = [
    {
      icon: <Landmark style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Destination Partnerships',
      tag: 'For Tourism Boards & DMOs',
      desc: 'Work with us to feature your destination in nexARound, through city guides, travel stories and local experiences. Talk to our team about a partnership.'
    },
    {
      icon: <HeartHandshake style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Experience Providers',
      tag: 'For Tour Operators & Activity Providers',
      desc: 'List your tours and activities in the app, then manage packages, availability, booking requests and reviews in the app or on the provider portal.',
      link: '/list-your-experience'
    },
    {
      icon: <Layers style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Museum & Cultural Site Partnerships',
      tag: 'For Museums & Cultural Sites',
      desc: 'Museum Master Guides cover more than 50 leading museums. Talk to us about featuring your museum or cultural site.'
    },
    {
      icon: <Globe style={{ width: '24px', height: '24px', color: 'var(--brand-teal)' }} />,
      title: 'Hotel Partnerships',
      tag: 'For Hotels & Resorts',
      desc: 'Talk to us about recommending your property and nearby experiences to travellers who plan their trips with nexARound.'
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
              Explore the AR discovery, AI trip planning, city guides and local experiences that make nexARound a complete travel companion.
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
              Work with nexARound to reach travellers planning trips to your destination.
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
                {m.link && (
                  <NavLink to={m.link} className="btn-teal" style={{ marginTop: '18px', padding: '10px 20px', fontSize: '0.85rem', textDecoration: 'none' }}>
                    <span>List your experience</span>
                    <ArrowRight style={{ width: '14px', height: '14px' }} />
                  </NavLink>
                )}
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
            Download the nexARound app today and explore with AR Discovery, Odyssey trip plans, City Guides and Neva.
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '20px' }}>
            <StoreButtons theme="dark" showRating={false} />
            <NavLink to="/get-app" style={{ fontSize: '0.92rem', color: 'var(--brand-teal)', fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: '6px', textDecoration: 'none' }}>
              <span>Learn more about device requirements &amp; QR codes</span>
              <ArrowRight style={{ width: '15px', height: '15px' }} />
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}

