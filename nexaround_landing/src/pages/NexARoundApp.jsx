import { NavLink } from 'react-router-dom';
import { 
  Sparkles, Camera, MapPin, Compass, BookOpen, 
  MessageSquare, Layers, Download, CheckCircle2, 
  ArrowRight, Smartphone, ShieldCheck, Zap, Globe,
  TrendingUp, Landmark, Users2, Cpu, Compass as CompassIcon
} from 'lucide-react';

export default function NexARoundApp() {
  const appFeatures = [
    {
      id: 'odyssey',
      num: '01',
      badge: 'Smart Itinerary Engine',
      title: 'Odyssey Plan',
      desc: 'An intelligent multi-day trip planner that automatically generates optimized, personalized travel itineraries balancing personal preferences, travel times, and real-time transit data.',
      icon: <Compass style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['Custom Multi-Day Itineraries', 'Route & Schedule Optimization', 'Dynamic Transit Integration']
    },
    {
      id: 'ar',
      num: '02',
      badge: 'Augmented Reality',
      title: 'AR Landmark Scanner',
      desc: 'Point your camera at historical monuments, ancient structures, or city landmarks for real-time visual recognition, interactive 3D overlays, and rich historical insights.',
      icon: <Camera style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['Real-Time Vision Camera', '3D Spatial Overlay', 'Instant Historical Context']
    },
    {
      id: 'neva',
      num: '03',
      badge: 'Conversational Concierge',
      title: 'Neva AI Chatbot',
      desc: 'A 24/7 personal travel assistant capable of answering destination queries, translating local languages, recommending hidden spots, and managing trip logistics live.',
      icon: <MessageSquare style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['24/7 Concierge Support', 'Multilingual Translation', 'Instant Destination Insights']
    },
    {
      id: 'around-you',
      num: '04',
      badge: 'Real-Time Radar',
      title: 'Around You',
      desc: 'A live discovery radar that detects nearby attractions, authentic local dining, cultural landmarks, and hidden spots tailored to your current GPS position.',
      icon: <MapPin style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['Proximity Attraction Radar', 'Local Food & Dining Finder', 'Hidden Gems & Micro-Tours']
    },
    {
      id: 'museum',
      num: '05',
      badge: 'Cultural Exploration',
      title: 'Museum Guide',
      desc: 'An interactive digital companion for heritage sites and museums. Offers step-by-step exhibit navigation, digital audio guides, and deep historical storytelling.',
      icon: <Landmark style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['Global Heritage Site Itineraries', 'Digital Audio Guides', 'Deep Exhibit Storytelling']
    },
    {
      id: 'stories',
      num: '06',
      badge: 'Travel Community',
      title: 'Travel Stories',
      desc: 'A visual community feed featuring authentic travel stories, photo logs, and curated destination guides shared by fellow travelers and local experts.',
      icon: <Globe style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['Visual Destination Guides', 'Verified Traveler Logs', 'Community Recommendations']
    },
    {
      id: 'journal',
      num: '07',
      badge: 'Digital Memory Log',
      title: 'My Travel Journal',
      desc: 'A personal digital diary that logs your trips, visited landmarks, travel statistics, photos, and notes into an archived memory collection.',
      icon: <BookOpen style={{ width: '26px', height: '26px', color: '#007A7C' }} />,
      highlights: ['Automatic Trip Memory Archive', 'Travel Stats & Milestones', 'Private Notes & Photo Logs']
    }
  ];

  const productCapabilities = [
    {
      icon: <CompassIcon style={{ width: '24px', height: '24px', color: '#007A7C' }} />,
      title: 'Intelligent Trip Planning',
      desc: 'Automated multi-day itinerary generation tailored to your interests, budget, and real-time schedules.'
    },
    {
      icon: <Camera style={{ width: '24px', height: '24px', color: '#007A7C' }} />,
      title: 'Spatial AR Camera Recognition',
      desc: 'Point your camera at monuments or temples to instantly reveal historical insights and interactive overlays.'
    },
    {
      icon: <Landmark style={{ width: '24px', height: '24px', color: '#007A7C' }} />,
      title: 'Cultural Heritage Guides',
      desc: 'Interactive museum exhibit exploration, guided walkthroughs, and rich digital audio storytelling.'
    }
  ];

  return (
    <div style={{ paddingBottom: '80px' }}>
      
      {/* ═══ HERO SECTION ═══ */}
      <section className="dark-section" style={{ position: 'relative', padding: '160px 0 100px', overflow: 'hidden', background: 'var(--navy)' }}>
        
        {/* Background Ambient Radial Glow */}
        <div style={{ position: 'absolute', top: '20%', left: '50%', transform: 'translateX(-50%)', width: '700px', height: '400px', background: 'radial-gradient(ellipse at center, rgba(0,122,124,0.25) 0%, rgba(10,22,40,0) 70%)', pointerEvents: 'none' }} />

        <div className="container" style={{ padding: '0 24px', position: 'relative', zIndex: 2 }}>
          <div style={{ maxWidth: '840px', margin: '0 auto', textAlign: 'center' }}>
            
            <div style={{ margin: '0 auto 20px', display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.78rem', fontWeight: 700, color: '#007A7C', background: 'rgba(0, 122, 124, 0.15)', padding: '6px 16px', borderRadius: '9999px', border: '1px solid rgba(0, 122, 124, 0.3)' }}>
              <Sparkles style={{ width: '14px', height: '14px', color: '#007A7C' }} /> Smart Tourism Mobile Ecosystem
            </div>

            <h1 style={{ fontSize: 'clamp(2.5rem, 5.5vw, 3.8rem)', fontWeight: 900, color: '#ffffff', lineHeight: 1.1, margin: '0 0 22px', letterSpacing: '-0.03em' }}>
              nexARound <br />
              <span className="text-gradient-teal">AI & AR Smart Tourism Companion</span>
            </h1>

            <p style={{ fontSize: '1.15rem', color: 'rgba(255, 255, 255, 0.8)', margin: '0 0 40px', lineHeight: 1.7, maxWidth: '740px', marginLeft: 'auto', marginRight: 'auto' }}>
              An all-in-one mobile companion that turns any smartphone into an intelligent local guide. Experience real-time AR landmark camera scanning, Odyssey AI trip planning, Neva 24/7 travel concierge, Around You location radar, and digital museum guides.
            </p>

            <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
              <a href="#download" className="btn-teal" style={{ padding: '14px 32px', fontSize: '0.95rem', display: 'inline-flex', alignItems: 'center', gap: '8px' }}>
                <Smartphone style={{ width: '18px', height: '18px' }} /> Download Mobile App
              </a>
              <a href="#features" className="btn-secondary" style={{ padding: '14px 28px', fontSize: '0.95rem', background: 'rgba(255, 255, 255, 0.05)', color: '#fff', borderColor: 'rgba(255, 255, 255, 0.2)', display: 'inline-flex', alignItems: 'center' }}>
                Explore 7 Product Modules
              </a>
            </div>

            {/* Quick Metrics */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px', marginTop: '64px', background: 'rgba(255, 255, 255, 0.03)', border: '1px solid rgba(255, 255, 255, 0.08)', borderRadius: '20px', padding: '24px 20px' }}>
              <div>
                <div style={{ fontSize: '1.8rem', fontWeight: 900, color: '#007A7C' }}>7 Modules</div>
                <div style={{ fontSize: '0.78rem', color: 'rgba(255, 255, 255, 0.65)', marginTop: '4px' }}>Unified Mobile Platform</div>
              </div>
              <div>
                <div style={{ fontSize: '1.8rem', fontWeight: 900, color: '#007A7C' }}>Real-Time AR</div>
                <div style={{ fontSize: '0.78rem', color: 'rgba(255, 255, 255, 0.65)', marginTop: '4px' }}>Camera Landmark Recognition</div>
              </div>
              <div>
                <div style={{ fontSize: '1.8rem', fontWeight: 900, color: '#10b981' }}>24/7 AI</div>
                <div style={{ fontSize: '0.78rem', color: 'rgba(255, 255, 255, 0.65)', marginTop: '4px' }}>Neva Smart Assistant</div>
              </div>
            </div>

          </div>
        </div>
      </section>

      {/* ═══ CORE PRODUCT CAPABILITIES ═══ */}
      <section style={{ padding: '80px 0', background: '#ffffff', borderBottom: '1px solid rgba(0, 122, 124, 0.1)' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          
          <div style={{ textAlign: 'center', maxWidth: '650px', margin: '0 auto 48px' }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.75rem', fontWeight: 700, color: '#007A7C', background: 'rgba(0, 122, 124, 0.08)', padding: '5px 14px', borderRadius: '9999px', border: '1px solid rgba(0, 122, 124, 0.2)', marginBottom: '14px' }}>
              <Sparkles style={{ width: '13px', height: '13px' }} /> Core Experience
            </div>
            <h2 style={{ fontSize: 'clamp(2rem, 3.5vw, 2.6rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
              Reinventing How You <span className="text-gradient-teal">Explore the World</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1rem', margin: 0, lineHeight: 1.6 }}>
              Three foundational pillars engineered to elevate every aspect of your travel experience.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '24px' }} className="grid-2">
            {productCapabilities.map((s, i) => (
              <div key={i} className="service-page-card" style={{ padding: '32px 28px' }}>
                <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(0, 122, 124, 0.08)', border: '1px solid rgba(0, 122, 124, 0.2)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '20px' }}>
                  {s.icon}
                </div>
                <h3 style={{ fontSize: '1.2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 10px' }}>
                  {s.title}
                </h3>
                <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                  {s.desc}
                </p>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ 7 PRODUCT MODULES ═══ */}
      <section id="features" style={{ padding: '100px 0', background: 'var(--bg-light)', position: 'relative', overflow: 'hidden' }}>
        
        {/* Ambient Glows */}
        <div style={{ position: 'absolute', top: '10%', right: '-5%', width: '400px', height: '400px', borderRadius: '50%', background: 'radial-gradient(circle, rgba(0,122,124,0.08) 0%, rgba(255,255,255,0) 70%)', pointerEvents: 'none' }} />

        <div className="container" style={{ padding: '0 24px', position: 'relative', zIndex: 2 }}>
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 64px' }}>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.75rem', fontWeight: 700, color: '#007A7C', background: 'rgba(0, 122, 124, 0.08)', padding: '5px 14px', borderRadius: '9999px', border: '1px solid rgba(0, 122, 124, 0.2)', marginBottom: '16px' }}>
              <Layers style={{ width: '13px', height: '13px' }} /> Product Architecture
            </div>
            <h2 style={{ fontSize: 'clamp(2.2rem, 4vw, 3rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 14px', lineHeight: 1.15, letterSpacing: '-0.02em' }}>
              7 Integrated <span className="text-gradient-teal">Feature Modules</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.7 }}>
              Engineered to deliver a seamless, intelligent tourism experience for modern travelers.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '28px' }} className="grid-2">
            {appFeatures.map((f, i) => (
              <div key={i} className="service-page-card" style={{ padding: '36px 32px' }}>
                <div>
                  
                  {/* Top Bar */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px' }}>
                    <div style={{ 
                      width: '56px', 
                      height: '56px', 
                      borderRadius: '16px', 
                      background: 'rgba(0, 122, 124, 0.08)', 
                      border: '1px solid rgba(0, 122, 124, 0.2)', 
                      display: 'flex', 
                      alignItems: 'center', 
                      justifyContent: 'center',
                      boxShadow: '0 4px 14px rgba(0, 122, 124, 0.08)'
                    }}>
                      {f.icon}
                    </div>

                    <span style={{ 
                      fontSize: '2.6rem', 
                      fontWeight: 900, 
                      color: 'rgba(0, 122, 124, 0.15)', 
                      fontFamily: 'var(--font-mono)', 
                      lineHeight: 1
                    }}>
                      {f.num}
                    </span>
                  </div>

                  <div style={{ fontSize: '0.78rem', fontWeight: 700, color: '#007A7C', textTransform: 'uppercase', letterSpacing: '0.8px', marginBottom: '8px' }}>
                    {f.badge}
                  </div>

                  <h3 style={{ fontSize: '1.35rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px', lineHeight: 1.25 }}>
                    {f.title}
                  </h3>

                  <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 24px' }}>
                    {f.desc}
                  </p>

                  {/* Highlights List */}
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', paddingTop: '16px', borderTop: '1px solid rgba(0, 122, 124, 0.1)' }}>
                    {f.highlights.map((h, idx) => (
                      <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.82rem', color: 'var(--navy)', fontWeight: 600 }}>
                        <CheckCircle2 style={{ width: '15px', height: '15px', color: '#007A7C', flexShrink: 0 }} />
                        {h}
                      </div>
                    ))}
                  </div>

                </div>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ REAL-TIME CLOUD & SPATIAL INTELLIGENCE ═══ */}
      <section className="dark-section" style={{ padding: '90px 0', position: 'relative', overflow: 'hidden', background: 'var(--navy)' }}>
        <div className="container" style={{ padding: '0 24px', position: 'relative', zIndex: 2 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '48px', alignItems: 'center' }} className="grid-2">
            
            <div>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.78rem', fontWeight: 700, color: '#007A7C', background: 'rgba(0, 122, 124, 0.15)', padding: '5px 14px', borderRadius: '9999px', border: '1px solid rgba(0, 122, 124, 0.3)', marginBottom: '16px' }}>
                <Cpu style={{ width: '13px', height: '13px' }} /> High-Performance Architecture
              </div>
              
              <h2 style={{ fontSize: 'clamp(2rem, 3.8vw, 2.8rem)', fontWeight: 800, color: '#ffffff', margin: '0 0 18px', lineHeight: 1.2, letterSpacing: '-0.02em' }}>
                Real-Time Cloud & <br />
                <span className="text-gradient-teal">Spatial Vision Intelligence</span>
              </h2>

              <p style={{ color: 'rgba(255, 255, 255, 0.75)', fontSize: '1.02rem', lineHeight: 1.7, margin: '0 0 28px' }}>
                Engineered for instant speed. nexARound leverages sub-second visual camera processing, live location telemetry, and multi-modal AI models to deliver accurate destination recommendations.
              </p>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                {[
                  'Sub-Second Vision Camera Landmark Identification',
                  'Live Proximity Telemetry & Food Radar',
                  'Multi-Modal Conversational AI Concierge',
                  'High-Availability Cloud Architecture'
                ].map((item, idx) => (
                  <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '0.9rem', color: '#ffffff', fontWeight: 600 }}>
                    <CheckCircle2 style={{ width: '16px', height: '16px', color: '#007A7C', flexShrink: 0 }} />
                    {item}
                  </div>
                ))}
              </div>
            </div>

            {/* Visual Card */}
            <div style={{ background: 'rgba(255, 255, 255, 0.04)', border: '1px solid rgba(0, 122, 124, 0.25)', borderRadius: '24px', padding: '40px 32px', textAlign: 'center' }}>
              <div style={{ width: '64px', height: '64px', borderRadius: '18px', background: 'rgba(0, 122, 124, 0.2)', border: '1px solid rgba(0, 122, 124, 0.3)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 20px' }}>
                <Zap style={{ width: '30px', height: '30px', color: '#007A7C' }} />
              </div>
              <h3 style={{ fontSize: '1.3rem', fontWeight: 800, color: '#ffffff', margin: '0 0 10px' }}>
                Cloud Spatial Engine
              </h3>
              <p style={{ fontSize: '0.88rem', color: 'rgba(255, 255, 255, 0.65)', lineHeight: 1.6, margin: 0 }}>
                High-throughput cloud backend built with Python/FastAPI and cross-platform Flutter client architecture.
              </p>
            </div>

          </div>
        </div>
      </section>

      {/* ═══ DOWNLOAD & TRIAL CTA ═══ */}
      <section id="download" className="container" style={{ padding: '100px 24px 0' }}>
        <div style={{ 
          padding: '64px 40px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(0,122,124,0.06) 0%, #ffffff 50%, rgba(26,86,219,0.04) 100%)', 
          border: '1px solid rgba(0,122,124,0.25)',
          borderRadius: '28px',
          boxShadow: '0 15px 50px -10px rgba(0,122,124,0.08)',
          maxWidth: '960px',
          margin: '0 auto'
        }}>
          <div style={{ marginBottom: '18px', display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.78rem', fontWeight: 700, color: '#007A7C', background: 'rgba(0,122,124,0.08)', padding: '5px 14px', borderRadius: '9999px', border: '1px solid rgba(0,122,124,0.2)' }}>
            <Sparkles style={{ width: '13px', height: '13px' }} /> Mobile Experience
          </div>

          <h2 style={{ fontSize: 'clamp(2rem, 4vw, 2.8rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.2 }}>
            Experience nexARound Today
          </h2>

          <p style={{ color: 'var(--text-secondary)', margin: '0 0 36px', fontSize: '1.05rem', maxWidth: '580px', marginLeft: 'auto', marginRight: 'auto', lineHeight: 1.7 }}>
            Download the mobile app build or request an enterprise demo of our spatial AI tourism platform.
          </p>

          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/contact" className="btn-teal" style={{ padding: '14px 32px', fontSize: '0.95rem', display: 'inline-flex', alignItems: 'center', gap: '8px' }}>
              <Sparkles style={{ width: '18px', height: '18px' }} /> Request Product Demo <ArrowRight style={{ width: '18px', height: '18px' }} />
            </NavLink>

            <NavLink to="/contact" className="btn-secondary" style={{ padding: '14px 28px', fontSize: '0.95rem', display: 'inline-flex', alignItems: 'center' }}>
              Contact Product Team
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
