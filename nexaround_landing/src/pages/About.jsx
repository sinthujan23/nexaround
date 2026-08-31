import { useState, useEffect } from 'react';
import { 
  Target, Cpu, GitCommit, CheckCircle2, ShieldCheck, 
  ArrowRight, Sparkles, Code2, Users, Layers, Lock, Award,
  Compass, Globe, Smartphone, Landmark
} from 'lucide-react';
import { NavLink } from 'react-router-dom';

const heroBackgrounds = [
  '/bg_colosseum_rome.png',
  '/bg_eiffel_tower.png',
  '/bg_sigiriya.png',
  '/bg_pyramids_giza.png',
  '/bg_taj_mahal.png',
  '/bg_machu_picchu.png',
  '/bg_great_wall.png',
  '/bg_sydney_opera.png',
  '/bg_statue_liberty.png',
];

export default function About() {
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);
  const values = [
    { title: 'Innovation with Purpose', desc: 'Blending spatial AR computing and artificial intelligence to enrich human cultural discovery.' },
    { title: 'Privacy & Security First', desc: 'Zero data brokering, enterprise-grade encryption, and strict GDPR/CCPA compliance.' },
    { title: 'Sub-Second Performance', desc: 'Edge computer vision and low-latency APIs engineered for seamless real-time exploration.' },
    { title: 'Cultural Integrity', desc: 'Collaborating with local historians and heritage authorities for authentic storytelling.' },
    { title: 'Global Accessibility', desc: 'Multi-lingual translation and intuitive UX designed for travelers of all ages and backgrounds.' }
  ];

  const expertises = [
    { name: 'Spatial AR & Computer Vision', desc: 'Real-time camera landmark recognition and 3D architectural overlays.' },
    { name: 'Conversational Travel AI', desc: 'Multi-modal LLMs customized for destination context and travel assistance.' },
    { name: 'Geo-Spatial Systems', desc: 'PostGIS spatial indexing and real-time proximity telemetry routing.' },
    { name: 'High-Concurrency Cloud', desc: 'Microservices architecture with Redis caching and Docker orchestration.' },
    { name: 'Cross-Platform Mobile', desc: 'High-performance Flutter applications with smooth 60fps native feel.' },
    { name: 'Enterprise ERP & Integrations', desc: 'Turnkey ERPNext systems, ticketing APIs, and partner booking gateways.' }
  ];

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
            key={bg}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              backgroundImage: `url(${bg})`,
              backgroundSize: 'cover',
              backgroundPosition: 'center 35%',
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
              Pioneering the Future of <span style={{ fontWeight: 500, color: '#00d2d3' }}>Intelligent Tourism</span>.
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
              NexAround is on a mission to transform how the world explores history, culture, and travel through spatial augmented reality and artificial intelligence.
            </p>

            {/* Action Buttons */}
            <div className="hero-btn-group" style={{ display: 'flex', gap: '14px', flexWrap: 'wrap', alignItems: 'center' }}>
              <NavLink 
                to="/get-app" 
                style={{ 
                  background: '#ffffff', 
                  color: '#000000', 
                  padding: '14px 28px', 
                  borderRadius: '9999px', 
                  fontSize: '15px', 
                  fontWeight: 600, 
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
                <span>Get the App</span>
                <ArrowRight style={{ width: '15px', height: '15px' }} />
              </NavLink>
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
                <span>Explore Features</span>
              </NavLink>
            </div>
          </div>
        </div>
      </section>

      {/* ═══ MISSION & VISION ═══ */}
      <section className="section-padding" style={{ background: '#ffffff' }}>
        <div className="container">
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '48px', alignItems: 'center' }} className="grid-2">
            
            <div style={{ textAlign: 'left' }}>
              <div className="badge badge-teal" style={{ marginBottom: '16px' }}>Our Mission</div>
              <h2 style={{ fontSize: 'clamp(2rem, 3.5vw, 2.8rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 18px', lineHeight: 1.2 }}>
                Making Every Journey <span className="text-gradient-teal">Unforgettable & Effortless</span>
              </h2>
              <p style={{ fontSize: '1.05rem', color: 'var(--text-secondary)', lineHeight: 1.75, margin: '0 0 20px' }}>
                We believe travel should be more than following static maps and tourist crowds. By pairing real-time camera computer vision with localized AI guidance, NexAround empowers travelers to understand the rich stories behind every monument, alley, and artifact.
              </p>
              <p style={{ fontSize: '1rem', color: 'var(--text-secondary)', lineHeight: 1.75, margin: 0 }}>
                From our engineering roots in Sri Lanka to global heritage destinations worldwide, our platform connects travelers, local businesses, and cultural heritage sites into one seamless digital ecosystem.
              </p>
            </div>

            <div style={{ position: 'relative' }}>
              <div style={{
                borderRadius: 'var(--radius-xl)',
                overflow: 'hidden',
                boxShadow: '0 25px 60px rgba(0, 122, 124, 0.2)',
                border: '1px solid rgba(0, 122, 124, 0.25)'
              }}>
                <img 
                  src="/nexaround_app_card_v2.png" 
                  alt="NexAround Mobile App in Action" 
                  style={{ width: '100%', height: 'auto', display: 'block', objectFit: 'cover' }} 
                  onError={(e) => { e.currentTarget.src = '/app_download_showcase.png'; }} 
                />
              </div>
            </div>

          </div>
        </div>
      </section>

      {/* ═══ CORE VALUES ═══ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)', borderTop: '1px solid var(--border-color)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>Our Values</div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              The Principles Behind <span className="text-gradient-teal">NexAround</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.7 }}>
              Guiding our design, algorithms, and engineering philosophy.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-3">
            {values.map((v, i) => (
              <div key={i} className="feature-card" style={{ textAlign: 'left' }}>
                <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '20px', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  <Award style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
                </div>
                <h3 style={{ fontSize: '1.25rem', fontWeight: 800, color: 'var(--dark-charcoal)', margin: '0 0 10px' }}>{v.title}</h3>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>{v.desc}</p>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ TECHNICAL EXPERTISE ═══ */}
      <section className="section-padding" style={{ background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>Core Competencies</div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              Engineering & <span className="text-gradient-teal">Technology Stack</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.7 }}>
              Deep domain capabilities powering our spatial mobile app and enterprise solutions.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-3">
            {expertises.map((exp, i) => (
              <div key={i} className="feature-card" style={{ textAlign: 'left' }}>
                <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '18px', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  <Cpu style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
                </div>
                <h3 style={{ fontSize: '1.18rem', fontWeight: 800, color: 'var(--dark-charcoal)', margin: '0 0 10px' }}>{exp.name}</h3>
                <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>{exp.desc}</p>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ CTA ═══ */}
      <section className="container" style={{ padding: '40px 32px 0' }}>
        <div style={{ 
          padding: '60px 40px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.08) 0%, #ffffff 50%, rgba(255, 184, 0, 0.05) 100%)', 
          border: '1px solid rgba(0, 122, 124, 0.3)',
          borderRadius: 'var(--radius-xl)',
          maxWidth: '900px',
          margin: '0 auto'
        }}>
          <h2 style={{ fontSize: 'clamp(2rem, 3.5vw, 2.8rem)', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
            Join Us in Reimagining Travel
          </h2>
          <p style={{ color: 'var(--text-secondary)', margin: '0 auto 32px', fontSize: '1.05rem', maxWidth: '560px', lineHeight: 1.7 }}>
            Experience NexAround today or speak to our team regarding destination partnerships and enterprise solutions.
          </p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/app" className="btn-teal">
              <span>Explore Mobile App</span>
              <ArrowRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
            <NavLink to="/contact" className="btn-secondary">
              Contact Leadership
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
