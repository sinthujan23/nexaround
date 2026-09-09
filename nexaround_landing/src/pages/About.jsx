import { useState, useEffect } from 'react';
import { 
  Target, Cpu, GitCommit, CheckCircle2, ShieldCheck, 
  ArrowRight, Sparkles, Code2, Users, Layers, Lock, Award,
  Compass, Globe, Smartphone, Landmark, MapPin
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

  const teamMembers = [
    { tag: 'PRODUCT ENGINEERING', title: 'Lead Software Engineer', desc: 'Leads development teams and delivers robust, scalable and high-performance software solutions.' },
    { tag: 'USER INTERFACE ENGINEERING', title: 'Lead Frontend Engineer', desc: 'Builds modern, responsive and intuitive user interfaces with a strong focus on performance and experience.' },
    { tag: 'SYSTEM ENGINEERING', title: 'Software Engineer', desc: 'Develops secure, efficient and scalable backend services and APIs that power our products.' },
    { tag: 'MOBILE ENGINEERING', title: 'Mobile Application Engineer', desc: 'Develops reliable mobile applications for Android and iOS with a focus on quality and performance.' },
    { tag: 'INFRASTRUCTURE & DEVOPS', title: 'DevOps Engineer', desc: 'Drives CI/CD, cloud infrastructure, pipelines and automation for reliable and seamless deployments.' },
    { tag: 'DATA INTELLIGENCE', title: 'Data Engineer', desc: 'Works with data pipelines, analytics and reporting to turn data into actionable insights.' },
    { tag: 'QUALITY ENGINEERING', title: 'QA Tester', desc: 'Ensures product quality through manual and automated testing with a keen eye for detail.' },
    { tag: 'SOFTWARE QUALITY', title: 'QA Tester', desc: 'Performs functional, regression and usability testing to deliver reliable and bug-free releases.' },
    { tag: 'RELEASE ENGINEERING', title: 'DevOps Engineer', desc: 'Automates infrastructure, optimizes deployment pipelines and ensures high availability and scalability.' },
    { tag: 'TECHNICAL SERVICES', title: 'Technical Support Engineer', desc: 'Provides technical support and ensures smooth communication across projects and teams.' },
    { tag: 'CLIENT SUCCESS', title: 'Client Support Manager', desc: 'Leads support operations and ensures exceptional client satisfaction.' },
    { tag: 'APPLICATION ENGINEERING', title: 'Associate Software Engineer', desc: 'Writes efficient code and collaborates on software delivery.' },
    { tag: 'BUSINESS STRATEGY', title: 'Business Analyst', desc: 'Bridges business requirements and technical delivery across client engagements.' },
    { tag: 'SOLUTION DEVELOPMENT', title: 'Software Engineer', desc: 'Full-stack development with a focus on PHP and MySQL systems.' },
    { tag: 'PEOPLE OPERATIONS', title: 'HR Manager & Management Executive', desc: 'Oversees HR and management operations.' }
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
              <h2 style={{ fontSize: 'clamp(2rem, 3.5vw, 2.8rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 18px', lineHeight: 1.2 }}>
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

      {/* ═══ FLAGSHIP PRODUCT (WE BUILD FOR OURSELVES TOO) ═══ */}
      <section style={{ 
        background: '#080a14', 
        padding: '54px 0', 
        borderTop: '1px solid rgba(255,255,255,0.08)', 
        borderBottom: '1px solid rgba(255,255,255,0.08)', 
        position: 'relative', 
        overflow: 'hidden' 
      }}>
        {/* Subtle glowing backdrop */}
        <div style={{
          position: 'absolute',
          top: '50%',
          left: '25%',
          transform: 'translate(-50%, -50%)',
          width: '500px',
          height: '500px',
          background: 'radial-gradient(circle, rgba(0, 210, 211, 0.12) 0%, rgba(8, 10, 20, 0) 70%)',
          pointerEvents: 'none',
          zIndex: 0
        }} />

        <div className="container" style={{ position: 'relative', zIndex: 1 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '56px', alignItems: 'center' }} className="grid-2">
            
            {/* Left: Flagship AI & AR Mobile App Showcase */}
            <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', position: 'relative', width: '100%' }}>
              <div 
                style={{
                  position: 'relative',
                  width: '100%',
                  maxWidth: '300px',
                  maxHeight: '450px',
                  borderRadius: '24px',
                  background: '#000000',
                  border: '1.5px solid rgba(255, 255, 255, 0.16)',
                  overflow: 'hidden',
                  boxShadow: '0 20px 50px -10px rgba(0, 0, 0, 0.85), 0 0 30px rgba(0, 210, 211, 0.22)',
                  transition: 'transform 0.4s cubic-bezier(0.25, 1, 0.35, 1), box-shadow 0.4s cubic-bezier(0.25, 1, 0.35, 1), border-color 0.4s cubic-bezier(0.25, 1, 0.35, 1)'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.transform = 'translateY(-4px) scale(1.01)';
                  e.currentTarget.style.borderColor = 'rgba(0, 210, 211, 0.45)';
                  e.currentTarget.style.boxShadow = '0 25px 60px -10px rgba(0, 0, 0, 0.9), 0 0 40px rgba(0, 210, 211, 0.35)';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.transform = 'translateY(0) scale(1)';
                  e.currentTarget.style.borderColor = 'rgba(255, 255, 255, 0.16)';
                  e.currentTarget.style.boxShadow = '0 20px 50px -10px rgba(0, 0, 0, 0.85), 0 0 30px rgba(0, 210, 211, 0.22)';
                }}
              >
                <img
                  src="/about_flagship_showcase.jpg?v=2"
                  alt="nexARound AI & AR Smart Tourism Companion"
                  style={{
                    width: '100%',
                    height: 'auto',
                    maxHeight: '450px',
                    display: 'block',
                    objectFit: 'cover'
                  }}
                />
              </div>
            </div>


            {/* Right: Content */}
            <div style={{ textAlign: 'left' }}>
              <div style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: '8px',
                padding: '6px 14px',
                borderRadius: '9999px',
                background: 'rgba(0, 210, 211, 0.12)',
                border: '1px solid rgba(0, 210, 211, 0.3)',
                color: '#00d2d3',
                fontSize: '0.8rem',
                fontWeight: 600,
                textTransform: 'uppercase',
                letterSpacing: '0.8px',
                marginBottom: '18px'
              }}>
                Flagship Product
              </div>

              <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3.2rem)', fontWeight: 500, color: '#ffffff', margin: '0 0 18px', lineHeight: 1.15, letterSpacing: '-0.02em' }}>
                We build for ourselves too
              </h2>

              <p style={{ fontSize: '1.05rem', color: 'rgba(255, 255, 255, 0.82)', lineHeight: 1.75, margin: '0 0 28px' }}>
                nexARound application is our flagship AI &amp; AR powered smart tourism companion, built entirely in-house. It is where our computer vision, conversational AI, mobile, and dynamic trip planning engineering come together in one innovative product.
              </p>

              <NavLink
                to="/app"
                style={{
                  display: 'inline-flex',
                  alignItems: 'center',
                  gap: '8px',
                  background: '#00d2d3',
                  color: '#080a14',
                  fontWeight: 600,
                  fontSize: '0.96rem',
                  padding: '14px 28px',
                  borderRadius: '9999px',
                  textDecoration: 'none',
                  boxShadow: '0 4px 20px rgba(0, 210, 211, 0.4)',
                  transition: 'all 0.25s ease'
                }}
                onMouseEnter={(e) => { e.currentTarget.style.transform = 'translateY(-2px)'; e.currentTarget.style.boxShadow = '0 6px 25px rgba(0, 210, 211, 0.6)'; }}
                onMouseLeave={(e) => { e.currentTarget.style.transform = 'translateY(0)'; e.currentTarget.style.boxShadow = '0 4px 20px rgba(0, 210, 211, 0.4)'; }}
              >
                <span>Explore the app</span>
                <ArrowRight style={{ width: '16px', height: '16px' }} />
              </NavLink>
            </div>

          </div>
        </div>
      </section>

      {/* ═══ CORE VALUES ═══ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)', borderTop: '1px solid var(--border-color)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>Our Values</div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
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
                <h3 style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 10px' }}>{v.title}</h3>
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
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
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
                <h3 style={{ fontSize: '1.18rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 10px' }}>{exp.name}</h3>
                <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>{exp.desc}</p>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ OUR TEAM & LEADERSHIP ═══ */}
      <section className="section-padding" style={{ background: '#ffffff', borderTop: '1px solid var(--border-color)' }}>
        <div className="container">
          
          {/* Header */}
          <div style={{ marginBottom: '40px', borderBottom: '2px solid var(--border-color)', paddingBottom: '20px' }}>
            <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', flexWrap: 'wrap', gap: '16px' }}>
              <div>
                <h2 style={{ fontSize: 'clamp(2.4rem, 4.5vw, 3.4rem)', fontWeight: 800, color: '#0044cc', margin: 0, lineHeight: 1.05, letterSpacing: '-0.03em', textTransform: 'uppercase' }}>
                  OUR TEAM
                </h2>
                <p style={{ fontSize: '1.12rem', color: 'var(--text-secondary)', fontWeight: 500, margin: '8px 0 0' }}>
                  The people behind NexARound Technologies
                </p>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <span style={{ fontSize: '0.8rem', fontWeight: 600, color: '#0044cc', background: 'rgba(0,68,204,0.08)', border: '1px solid rgba(0,68,204,0.2)', padding: '6px 14px', borderRadius: '9999px' }}>
                  Global Talent
                </span>
                <span style={{ fontSize: '0.8rem', fontWeight: 600, color: 'var(--dark-charcoal)', background: 'rgba(10,17,24,0.06)', border: '1px solid var(--border-color)', padding: '6px 14px', borderRadius: '9999px' }}>
                  15+ Disciplines
                </span>
              </div>
            </div>
          </div>

          {/* Leadership Row */}
          <div style={{ display: 'grid', gridTemplateColumns: '190px 1fr', gap: '24px', marginBottom: '32px', alignItems: 'stretch' }} className="team-responsive-split">
            {/* Leadership Pill/Badge */}
            <div style={{
              background: 'linear-gradient(145deg, #091a38 0%, #030b1c 100%)',
              borderRadius: '18px',
              padding: '28px 20px',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
              alignItems: 'center',
              textAlign: 'center',
              color: '#ffffff',
              boxShadow: '0 10px 28px -6px rgba(9,26,56,0.4)',
              border: '1px solid rgba(255,255,255,0.1)'
            }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.95rem', fontWeight: 800, letterSpacing: '2px', textTransform: 'uppercase', color: '#38bdf8' }}>
                LEADERSHIP
              </span>
              <div style={{ width: '32px', height: '3px', background: '#00d2d3', margin: '12px auto 0', borderRadius: '9999px' }} />
            </div>

            {/* Leadership Content Card */}
            <div style={{
              background: '#f8fafc',
              border: '1px solid #e2e8f0',
              borderRadius: '18px',
              padding: '30px 36px',
              display: 'flex',
              gap: '28px',
              alignItems: 'center',
              boxShadow: '0 8px 24px -8px rgba(0,0,0,0.04)'
            }} className="team-leadership-card">
              <div style={{
                width: '76px',
                height: '76px',
                borderRadius: '50%',
                background: 'linear-gradient(135deg, #e0f2fe 0%, #bae6fd 100%)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                flexShrink: 0,
                boxShadow: '0 6px 16px rgba(2,132,199,0.18)',
                border: '2px solid #ffffff'
              }}>
                <Users style={{ width: '36px', height: '36px', color: '#0284c7' }} />
              </div>
              <div style={{ fontSize: '0.96rem', lineHeight: 1.75, color: '#334155' }}>
                <p style={{ margin: '0 0 12px' }}>
                  Our leadership is powered by industry veterans with decades of global experience across multiple geographies and high-impact sectors. They represent a unique blend of deep financial leadership and enterprise technology expertise, with a proven track record of architecting and delivering enterprise-scale ICT and digital transformation programs across <strong>Finance, Sports, Government, Healthcare, Insurance, Education, and Manufacturing</strong> domains.
                </p>
                <p style={{ margin: 0, color: '#64748b' }}>
                  Their collective experience has enabled organizations to transform complexity into competitive advantage through technology-led innovation, operational excellence, and sustainable growth.
                </p>
              </div>
            </div>
          </div>

          {/* Team Grid Row */}
          <div style={{ display: 'grid', gridTemplateColumns: '190px 1fr', gap: '24px', alignItems: 'stretch' }} className="team-responsive-split">
            {/* Team Left Pill/Badge */}
            <div style={{
              background: 'linear-gradient(145deg, #091a38 0%, #030b1c 100%)',
              borderRadius: '18px',
              padding: '36px 18px',
              display: 'flex',
              flexDirection: 'column',
              justifyContent: 'center',
              alignItems: 'center',
              textAlign: 'center',
              color: '#ffffff',
              boxShadow: '0 10px 28px -6px rgba(9,26,56,0.4)',
              border: '1px solid rgba(255,255,255,0.1)'
            }}>
              <span style={{ fontFamily: 'var(--font-mono)', fontSize: '1.15rem', fontWeight: 800, letterSpacing: '1.5px', textTransform: 'uppercase', color: '#ffffff' }}>
                OUR TEAM
              </span>
              <div style={{ width: '28px', height: '3px', background: '#0044cc', margin: '12px auto 14px', borderRadius: '9999px' }} />
              <p style={{ fontSize: '0.88rem', color: '#94a3b8', lineHeight: 1.45, margin: 0, fontWeight: 500 }}>
                Engineers, Architects &amp; Designers
              </p>
            </div>

            {/* 15 Role Cards Grid */}
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
              gap: '14px'
            }}>
              {teamMembers.map((member, idx) => (
                <div
                  key={idx}
                  style={{
                    background: '#ffffff',
                    border: '1px solid #dbeafe',
                    borderRadius: '14px',
                    overflow: 'hidden',
                    display: 'flex',
                    flexDirection: 'column',
                    boxShadow: '0 4px 14px -3px rgba(14,49,117,0.06)',
                    transition: 'all 0.25s ease'
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.transform = 'translateY(-3px)';
                    e.currentTarget.style.boxShadow = '0 10px 24px -4px rgba(0,68,204,0.15)';
                    e.currentTarget.style.borderColor = '#93c5fd';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.transform = 'translateY(0)';
                    e.currentTarget.style.boxShadow = '0 4px 14px -3px rgba(14,49,117,0.06)';
                    e.currentTarget.style.borderColor = '#dbeafe';
                  }}
                >
                  <div style={{
                    background: '#0044cc',
                    color: '#ffffff',
                    padding: '8px 10px',
                    fontSize: '0.64rem',
                    fontWeight: 700,
                    textAlign: 'center',
                    letterSpacing: '0.6px',
                    textTransform: 'uppercase',
                    fontFamily: 'var(--font-mono)'
                  }}>
                    {member.tag}
                  </div>
                  <div style={{ padding: '14px 12px 16px', display: 'flex', flexDirection: 'column', flex: 1 }}>
                    <h4 style={{ fontSize: '0.92rem', fontWeight: 700, color: '#0038a8', margin: '0 0 6px', lineHeight: 1.25 }}>
                      {member.title}
                    </h4>
                    <p style={{ fontSize: '0.78rem', lineHeight: 1.45, color: '#475569', margin: 0 }}>
                      {member.desc}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>

        </div>
      </section>

      {/* ═══ GLOBAL OFFICES / PRESENCE ═══ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)', borderTop: '1px solid var(--border-color)', borderBottom: '1px solid var(--border-color)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 60px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '16px' }}>Global Presence</div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 3.8vw, 3rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', letterSpacing: '-0.025em' }}>
              Our Global <span className="text-gradient-teal">Offices</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.7 }}>
              NexAround operates internationally across three continents with strategic corporate and engineering hubs in the UAE, the United Kingdom, and Sri Lanka.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-3">
            
            {/* UAE Office */}
            <div className="feature-card" style={{ textAlign: 'left', display: 'flex', flexDirection: 'column' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px' }}>
                <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  <MapPin style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
                </div>
                <span style={{ fontSize: '0.78rem', fontWeight: 600, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.08)', padding: '4px 10px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  UAE 🇦🇪
                </span>
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 6px' }}>UAE Office</h3>
              <div style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--brand-teal)', marginBottom: '12px' }}>NEXAROUND TECHNOLOGIES L.L.C</div>
              <address style={{ fontStyle: 'normal', fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                Property Investment Office 4 - S1, Plot Number 516-0,<br />
                Dubai Investment Park First, Dubai, United Arab Emirates
              </address>
            </div>

            {/* UK Office */}
            <div className="feature-card" style={{ textAlign: 'left', display: 'flex', flexDirection: 'column' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px' }}>
                <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  <MapPin style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
                </div>
                <span style={{ fontSize: '0.78rem', fontWeight: 600, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.08)', padding: '4px 10px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  United Kingdom 🇬🇧
                </span>
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 6px' }}>UK Office</h3>
              <div style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--brand-teal)', marginBottom: '12px' }}>NEXAROUND LTD</div>
              <address style={{ fontStyle: 'normal', fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                Office 20243, 182-184 High Street North,<br />
                East Ham, London, United Kingdom, E6 2JA
              </address>
            </div>

            {/* Sri Lanka Office */}
            <div className="feature-card" style={{ textAlign: 'left', display: 'flex', flexDirection: 'column' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px' }}>
                <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1px solid rgba(0, 122, 124, 0.25)' }}>
                  <MapPin style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
                </div>
                <span style={{ fontSize: '0.78rem', fontWeight: 600, color: 'var(--brand-teal)', background: 'rgba(0, 122, 124, 0.08)', padding: '4px 10px', borderRadius: '9999px', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                  Sri Lanka 🇱🇰
                </span>
              </div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 6px' }}>Colombo Office</h3>
              <div style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--brand-teal)', marginBottom: '12px' }}>NEXAROUND</div>
              <address style={{ fontStyle: 'normal', fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                No.47/3/1/1, 4th Lane, Madiwela,<br />
                Kotte, Colombo, Sri Lanka
              </address>
            </div>

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
          <h2 style={{ fontSize: 'clamp(2rem, 3.5vw, 2.8rem)', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 16px', lineHeight: 1.2 }}>
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
