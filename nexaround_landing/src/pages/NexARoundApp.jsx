import { useState, useEffect } from 'react';
import { NavLink } from 'react-router-dom';
import {
  Sparkles, Layers, CheckCircle2, ArrowRight, ArrowUpRight, ChevronDown, ChevronUp
} from 'lucide-react';
import StoreButtons from '../components/StoreButtons';
import AppScreen from '../components/AppScreen';
import { APP_MODULES } from '../data/appModules';

const heroBackgrounds = [
  { name: 'Colosseum, Rome', src: '/bg_colosseum_rome.png' },
  { name: 'Eiffel Tower, Paris', src: '/bg_eiffel_tower.png' },
  { name: 'Sigiriya Citadel, Sri Lanka', src: '/bg_sigiriya.png' },
  { name: 'Pyramids of Giza, Egypt', src: '/bg_pyramids_giza.png' },
  { name: 'Taj Mahal, India', src: '/bg_taj_mahal.png' },
  { name: 'Machu Picchu, Peru', src: '/bg_machu_picchu.png' },
  { name: 'Great Wall of China', src: '/bg_great_wall.png' },
  { name: 'Sydney Opera House, Australia', src: '/bg_sydney_opera.png' },
  { name: 'Statue of Liberty, New York', src: '/bg_statue_liberty.png' },
];

export default function NexARoundApp() {
  const [expandedStory, setExpandedStory] = useState(false);
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  // Auto-rotate hero background images with smooth crossfade
  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);

  // The app's features, shared with the Home page (src/data/appModules.js)
  const appFeatures = APP_MODULES.map((m, i) => ({
    ...m,
    num: String(i + 1).padStart(2, '0'),
    subtitle: m.short,
    iconNode: <m.icon style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
  }));

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '80px' }}>
      
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
            key={bg.src}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              backgroundImage: `url(${bg.src})`,
              backgroundSize: 'cover',
              backgroundPosition: 'center 35%',
              opacity: idx === currentBgIndex ? 0.6 : 0,
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

        {/* Hero Content (Exact Matching Reference Screenshot) */}
        <div className="container" style={{ position: 'relative', zIndex: 3 }}>
          <div style={{ maxWidth: '820px', textAlign: 'left' }}>
            
            {/* Breadcrumb */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '24px', fontSize: '0.88rem', color: 'rgba(255, 255, 255, 0.7)' }}>
              <NavLink to="/" style={{ color: 'rgba(255, 255, 255, 0.8)', textDecoration: 'none' }}>Home</NavLink>
              <span style={{ opacity: 0.6 }}>›</span>
              <span style={{ color: 'rgba(255, 255, 255, 0.95)', fontWeight: 500 }}>nexARound App</span>
            </div>

            {/* App Icon + Title */}
            <div style={{ display: 'flex', alignItems: 'center', gap: '20px', marginBottom: '16px', flexWrap: 'wrap' }}>
              <div style={{
                width: '74px',
                height: '74px',
                borderRadius: '18px',
                background: '#ffffff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                padding: '6px',
                boxShadow: '0 8px 30px rgba(0, 0, 0, 0.45)',
                border: '1px solid rgba(255, 255, 255, 0.2)'
              }}>
                <img 
                  src="/logo_2.png" 
                  alt="nexARound Icon" 
                  style={{ width: '56px', height: '56px', objectFit: 'contain' }} 
                  onError={(e) => { e.currentTarget.src = '/logo_2_icon_clean.png'; }}
                />
              </div>

              <h1 style={{ 
                fontSize: 'clamp(3rem, 6vw, 4.8rem)', 
                fontWeight: 500, 
                color: '#ffffff', 
                letterSpacing: '-0.03em', 
                lineHeight: 1, 
                margin: 0,
                textShadow: '0 2px 14px rgba(0,0,0,0.5)'
              }}>
                nex<span>ARound</span>
              </h1>
            </div>

            {/* Sub-Headline / Quote */}
            <h2 style={{ 
              fontSize: 'clamp(1.3rem, 2.4vw, 1.95rem)', 
              fontWeight: 500, 
              color: '#ffffff', 
              lineHeight: 1.3, 
              margin: '0 0 18px',
              letterSpacing: '-0.015em',
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              "Discover What's Next Around You!"
            </h2>

            {/* Subtitle / Paragraph */}
            <p style={{ 
              fontSize: 'clamp(1rem, 1.6vw, 1.18rem)', 
              color: 'rgba(255, 255, 255, 0.88)', 
              lineHeight: 1.65, 
              margin: '0 0 34px', 
              maxWidth: '680px',
              fontWeight: 300,
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              Every place has a story and every street hides a surprise. nexARound is your AI-powered smart tourism companion that helps you discover authentic local experiences, right here, right now.
            </p>

            {/* Action Buttons */}
            <div className="hero-btn-group" style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
              <NavLink 
                to="/get-app" 
                className="btn-white-pill"
                style={{ padding: '12px 26px', fontSize: '0.95rem' }}
              >
                <span>Get the app</span>
                <ArrowUpRight style={{ width: '17px', height: '17px' }} />
              </NavLink>

              <NavLink 
                to="/about"
                className="btn-glass"
                style={{ padding: '12px 26px', fontSize: '0.95rem' }}
              >
                <span>Read our story</span>
              </NavLink>
            </div>
          </div>
        </div>
      </section>

      {/* ═══ BRAND STORY (3 PILLARS) ═══ */}
      <section id="story" style={{ padding: '90px 0', background: 'var(--bg-light)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '720px', margin: '0 auto 56px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Sparkles style={{ width: '14px', height: '14px' }} /> The Brand Story
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              The Story Behind <span className="text-gradient-teal">nexARound</span>
            </h2>
            <p style={{ fontSize: '1.08rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.7 }}>
              The name <strong>nexARound</strong> brings together three powerful ideas into one seamless travel companion.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px', marginBottom: '40px' }} className="grid-3">
            <div className="feature-card" style={{ padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                01 • Discovery
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>nex(t)</h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Your next adventure, your next discovery, your next unforgettable moment waiting around the corner.
              </p>
            </div>

            <div className="feature-card" style={{ padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                02 • Surroundings
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>ARound</h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Everything around you, from hidden cafés and scenic viewpoints to authentic food, culture and local experiences.
              </p>
            </div>

            <div className="feature-card" style={{ padding: '36px 30px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '10px' }}>
                03 • Technology
              </span>
              <h3 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>Augmented Reality (AR)</h3>
              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                Simply raise your phone to see nearby attractions, food, shopping and hotels over the camera view.
              </p>
            </div>
          </div>

          <div style={{
            background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)',
            border: '1px solid rgba(0, 122, 124, 0.25)',
            borderRadius: 'var(--radius-lg)',
            padding: '36px 40px',
            textAlign: 'center',
            maxWidth: '960px',
            margin: '0 auto'
          }}>
            <p style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 8px', fontStyle: 'italic' }}>
              "What can I discover next around me, right here, right now?"
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--brand-teal)', fontWeight: 500, margin: '0 0 16px' }}>
              Because travel isn't just about reaching a destination- it's about moments that become lifelong memories.
            </p>
            <button 
              onClick={() => setExpandedStory(!expandedStory)}
              style={{
                background: 'none',
                border: 'none',
                color: 'var(--brand-teal)',
                fontWeight: 500,
                fontSize: '0.92rem',
                cursor: 'pointer',
                display: 'inline-flex',
                alignItems: 'center',
                gap: '6px'
              }}
            >
              <span>{expandedStory ? 'Show Less' : 'Read Full Mission Statement'}</span>
              {expandedStory ? <ChevronUp style={{ width: '16px', height: '16px' }} /> : <ChevronDown style={{ width: '16px', height: '16px' }} />}
            </button>

            {expandedStory && (
              <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginTop: '16px', paddingTop: '16px', borderTop: '1px solid var(--border-color)', textAlign: 'left' }}>
                NexAround is an AI-powered Tourism Companion that transforms how people explore destinations around the world. It uses your location, mood, budget and available time to plan days that suit you.
              </p>
            )}
          </div>

        </div>
      </section>

      {/* ═══ 10 PRODUCT MODULES DEEP-DIVE ═══ */}
      <section id="modules" style={{ padding: '100px 0', background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '700px', margin: '0 auto 64px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>
              <Layers style={{ width: '14px', height: '14px' }} /> Complete App Capabilities
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              14 App <span className="text-gradient-teal">Feature Modules</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.08rem', margin: 0, lineHeight: 1.7 }}>
              Engineered to deliver an intelligent, effortless travel companion from the moment you plan your trip to when you step foot in the destination.
            </p>
          </div>

          {/* Module Cards Grid */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '36px' }}>
            {appFeatures.map((mod, idx) => (
              <div 
                key={mod.id} 
                id={mod.id}
                className="feature-card" 
                style={{ 
                  scrollMarginTop: '110px',
                  padding: '48px 44px',
                  background: idx % 2 === 1 ? 'linear-gradient(135deg, rgba(0, 122, 124, 0.03) 0%, #ffffff 100%)' : '#ffffff'
                }}
              >
                <div style={{ 
                  display: 'grid', 
                  gridTemplateColumns: idx % 2 === 0 ? '1.2fr 1fr' : '1fr 1.2fr', 
                  gap: '48px', 
                  alignItems: 'center' 
                }} className="grid-2">
                  
                  {/* Left or Text Content */}
                  <div style={{ order: idx % 2 === 0 ? 1 : 2, textAlign: 'left' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
                      <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                        {mod.iconNode}
                      </div>
                      <span style={{ fontSize: '0.78rem', fontWeight: 500, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.08)', padding: '6px 14px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.8px' }}>
                        Module {mod.num} • {mod.badge}
                      </span>
                    </div>

                    <h3 style={{ fontSize: 'clamp(1.8rem, 3vw, 2.3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 8px', lineHeight: 1.2 }}>
                      {mod.title}
                    </h3>

                    <div style={{ fontSize: '1.02rem', fontWeight: 500, color: 'var(--brand-teal)', marginBottom: '16px' }}>
                      {mod.subtitle}
                    </div>

                    <p style={{ fontSize: '1rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 24px' }}>
                      {mod.desc}
                    </p>

                    <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginBottom: '28px', paddingTop: '16px', borderTop: '1px solid var(--border-color)' }}>
                      {mod.highlights.map((h, i) => (
                        <div key={i} style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '0.92rem', color: 'var(--dark-charcoal)', fontWeight: 500 }}>
                          <CheckCircle2 style={{ width: '16px', height: '16px', color: 'var(--brand-teal)', flexShrink: 0 }} />
                          {h}
                        </div>
                      ))}
                    </div>

                    <NavLink to="/get-app" className="btn-teal" style={{ padding: '12px 26px', fontSize: '0.9rem', textDecoration: 'none' }}>
                      <span>Try in App</span>
                      <ArrowRight style={{ width: '16px', height: '16px' }} />
                    </NavLink>
                  </div>

                  {/* Mockup Preview */}
                  <div style={{ order: idx % 2 === 0 ? 2 : 1, display: 'flex', justifyContent: 'center' }}>
                    <div style={{
                      maxWidth: '300px',
                      borderRadius: '28px',
                      overflow: 'hidden',
                      boxShadow: '0 20px 50px rgba(10, 17, 24, 0.22)',
                      border: '6px solid #111a24',
                      background: '#111a24'
                    }}>
                      <AppScreen module={mod} />
                    </div>
                  </div>

                </div>
              </div>
            ))}
          </div>

        </div>
      </section>



      {/* ═══ FOR EXPERIENCE PROVIDERS ═══ */}
      <section className="container" style={{ padding: '80px 32px 0' }}>
        <div className="feature-card" style={{ padding: '44px 38px', textAlign: 'left', maxWidth: '960px', margin: '0 auto' }}>
          <div className="badge badge-teal" style={{ marginBottom: '16px' }}>For experience providers</div>
          <h2 style={{ fontSize: 'clamp(1.8rem, 3vw, 2.4rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 12px' }}>
            Run your experiences from the app
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '1.02rem', lineHeight: 1.7, margin: '0 0 22px' }}>
            Run tours, boat trips or activities? Apply here or from the app. Once you are listed, manage your packages, availability, booking requests and reviews in the app or on the provider portal.
          </p>
          <div style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
            <NavLink to="/list-your-experience" className="btn-teal" style={{ padding: '12px 26px', fontSize: '0.9rem', textDecoration: 'none' }}>
              <span>List your experience</span>
              <ArrowRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
            <a href="https://partner.nexaround.com" className="btn-secondary" style={{ padding: '12px 26px', fontSize: '0.9rem', textDecoration: 'none' }}>
              <span>Open the provider portal</span>
              <ArrowUpRight style={{ width: '16px', height: '16px' }} />
            </a>
          </div>
        </div>
      </section>

      {/* ═══ EXPLORE CTA ═══ */}
      <section className="container" style={{ padding: '80px 32px 0' }}>
        <div className="app-cta-card" style={{ 
          padding: '60px 44px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)', 
          border: '1px solid rgba(0, 122, 124, 0.25)',
          borderRadius: 'var(--radius-xl)',
          boxShadow: '0 20px 50px -10px rgba(0, 122, 124, 0.1)',
          maxWidth: '960px',
          margin: '0 auto'
        }}>
          <div className="badge badge-teal" style={{ marginBottom: '18px' }}>
            <Sparkles style={{ width: '14px', height: '14px' }} /> Ready to Explore?
          </div>

          <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3.2rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
            Start Your Journey with NexAround
          </h2>

          <p style={{ color: 'var(--text-secondary)', margin: '0 auto 36px', fontSize: '1.08rem', maxWidth: '600px', lineHeight: 1.7 }}>
            Plan trips with Odyssey, explore with AR Discovery and City Guides, and ask Neva anything, all on your smartphone.
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
