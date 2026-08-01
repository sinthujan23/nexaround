import { NavLink } from 'react-router-dom';
import {
  Code2, BrainCircuit, Blocks, Cloud, ArrowRight, Sparkles,
  Repeat, Monitor, Cpu, Palette, ShieldCheck,
  Building2, GraduationCap, Briefcase, Factory, HardHat,
  Radio, Zap, Headphones, ChevronRight, Smartphone,
  CheckCircle2
} from 'lucide-react';

export default function Home() {
  const services = [
    { num: '01', icon: <Repeat style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Digital Transformation', desc: 'Reimagine operations end-to-end with modern, connected systems and clear execution roadmaps.' },
    { num: '02', icon: <Code2 style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Software Engineering', desc: 'Custom, full-stack enterprise development delivered with quality and scale built in from day one.' },
    { num: '03', icon: <Cloud style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Cloud Implementation', desc: 'Cloud-native architecture, DevOps, and secure infrastructure that scales seamlessly with your growth.' },
    { num: '04', icon: <BrainCircuit style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'AI, ML & Data', desc: 'Predictive models, intelligent automation, and data pipelines that convert raw information into decisions.' },
    { num: '05', icon: <Palette style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'UI / UX Design', desc: 'Human-centred digital interfaces that are intuitive to use and visually captivating.' },
    { num: '06', icon: <ShieldCheck style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Quality & Automation', desc: 'Automated testing and quality engineering ensuring every production release ships with full confidence.' },
  ];

  const industries = [
    { icon: <Building2 style={{ width: '22px', height: '22px' }} />, name: 'Public Sector & NGOs' },
    { icon: <GraduationCap style={{ width: '22px', height: '22px' }} />, name: 'Education & Academia' },
    { icon: <Briefcase style={{ width: '22px', height: '22px' }} />, name: 'Corporate & Private' },
    { icon: <Factory style={{ width: '22px', height: '22px' }} />, name: 'Manufacturing & Industry' },
    { icon: <HardHat style={{ width: '22px', height: '22px' }} />, name: 'Construction Sector' },
    { icon: <Radio style={{ width: '22px', height: '22px' }} />, name: 'Telecom Sector' },
    { icon: <Zap style={{ width: '22px', height: '22px' }} />, name: 'Energy Sector' },
    { icon: <Headphones style={{ width: '22px', height: '22px' }} />, name: 'Service Sector' },
  ];

  const solutions = [
    { icon: <Monitor style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, tag: 'Enterprise ERP Suite', title: 'ERPNext & Business Systems', desc: 'End-to-end ERPNext implementation, custom module engineering, and ongoing corporate support.' },
    { icon: <BrainCircuit style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, tag: 'Intelligence Engine', title: 'AI, ML & Data Systems', desc: 'Intelligent solutions utilizing machine learning models, LLM document parsing, and BI dashboards.' },
    { icon: <Blocks style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, tag: 'Decentralized Trust', title: 'Blockchain & Web3 Platform', desc: 'Audited smart contracts, decentralized dApps, asset tokenization engines, and Web3 gateways.' },
    { icon: <Cloud style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, tag: 'Cloud Architecture', title: 'Cloud Infrastructure & DevOps', desc: 'Scalable cloud infrastructure, IaC automation, CI/CD pipelines, and multi-region failover.' },
  ];

  return (
    <div>
      
      {/* ═══ HERO (Immersive Dark Full-Bleed Section) ═══ */}
      <section className="dark-section" style={{ position: 'relative', minHeight: '88vh', display: 'flex', alignItems: 'center', overflow: 'hidden', padding: '170px 0 110px' }}>
        
        {/* Dark High-Tech Background Image Overlay */}
        <img 
          src="/hero_bg.png" 
          alt="Modern Enterprise Software Engineering Hero Background"
          style={{ 
            position: 'absolute', 
            top: 0, 
            left: 0, 
            width: '100%', 
            height: '100%', 
            objectFit: 'cover', 
            zIndex: 1, 
            pointerEvents: 'none', 
            opacity: 0.48,
            filter: 'contrast(1.05) brightness(0.95)'
          }}
        />

        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, rgba(10,22,40,0.35), rgba(10,22,40,0.85))', zIndex: 1, pointerEvents: 'none' }} />

        <div className="container" style={{ position: 'relative', zIndex: 2, textAlign: 'left' }}>
          <div style={{ maxWidth: '960px', textAlign: 'left' }}>
            
            {/* Pillar Capsules */}
            <div style={{ display: 'flex', gap: '12px', marginBottom: '32px', flexWrap: 'wrap', justifyContent: 'flex-start', alignItems: 'center' }}>
              {[
                { icon: <Code2 style={{ width: '16px', height: '16px', color: '#60a5fa' }} />, label: 'Full-Stack Engineering' },
                { icon: <BrainCircuit style={{ width: '16px', height: '16px', color: '#60a5fa' }} />, label: 'AI & Data' },
                { icon: <Blocks style={{ width: '16px', height: '16px', color: '#60a5fa' }} />, label: 'Blockchain' },
                { icon: <Cloud style={{ width: '16px', height: '16px', color: '#60a5fa' }} />, label: 'Cloud & ERP' },
              ].map((p, i) => (
                <div key={i} style={{ 
                  display: 'inline-flex', 
                  alignItems: 'center', 
                  gap: '8px', 
                  fontSize: '0.73rem', 
                  fontWeight: 700, 
                  textTransform: 'uppercase', 
                  letterSpacing: '0.6px', 
                  color: '#ffffff',
                  background: 'rgba(15, 23, 42, 0.75)',
                  backdropFilter: 'blur(16px)',
                  WebkitBackdropFilter: 'blur(16px)',
                  border: '1px solid rgba(255, 255, 255, 0.2)',
                  padding: '8px 14px',
                  borderRadius: '12px',
                  boxShadow: '0 4px 20px rgba(0, 0, 0, 0.3)'
                }}>
                  <div style={{
                    width: '26px',
                    height: '26px',
                    borderRadius: '7px',
                    background: 'rgba(96, 165, 250, 0.18)',
                    border: '1px solid rgba(96, 165, 250, 0.35)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexShrink: 0
                  }}>
                    {p.icon}
                  </div>
                  <span>{p.label}</span>
                </div>
              ))}
            </div>

            <h1 style={{ fontSize: 'clamp(2.6rem, 5vw, 4.2rem)', fontWeight: 800, color: '#ffffff', lineHeight: 1.15, margin: '0 0 22px', letterSpacing: '-0.03em', textAlign: 'left', whiteSpace: 'nowrap' }}>
              NexARound <span className="text-gradient-blue">Technologies</span>
            </h1>

            <p style={{ fontSize: '1.45rem', fontWeight: 600, color: '#ffffff', margin: '0 0 18px', lineHeight: 1.35, textAlign: 'left' }}>
              Full-stack engineering to fast-track your growth.
            </p>

            <p style={{ fontSize: '1.12rem', color: 'rgba(255, 255, 255, 0.85)', margin: '0 0 40px', lineHeight: 1.65, maxWidth: '900px', textAlign: 'left' }}>
              Tailored digital solutions for every sector. We help businesses, institutions, and communities design, build, and scale intelligent software systems — across Sri Lanka and beyond.
            </p>

            <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap', justifyContent: 'flex-start' }}>
              <NavLink to="/solutions" className="btn-white-pill">
                Explore Solutions <ArrowRight style={{ width: '18px', height: '18px' }} />
              </NavLink>
              <NavLink to="/app" className="btn-secondary">
                Flagship App Showcase
              </NavLink>
            </div>

          </div>
        </div>

      </section>

      {/* ═══ FLAGSHIP APP SPOTLIGHT BANNER (Alternating Split Grid) ═══ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)', position: 'relative', overflow: 'hidden' }}>
        <div className="container" style={{ position: 'relative', zIndex: 2 }}>
          
          <div style={{
            background: 'linear-gradient(135deg, rgba(0, 122, 124, 0.05) 0%, #ffffff 50%, rgba(26, 86, 219, 0.03) 100%)',
            border: '1px solid rgba(0, 122, 124, 0.22)',
            borderRadius: 'var(--radius-lg)',
            padding: '56px 48px',
            boxShadow: '0 15px 45px -10px rgba(0, 122, 124, 0.08)',
            position: 'relative',
            overflow: 'hidden'
          }}>

            <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '52px', alignItems: 'center' }} className="grid-2">
              
              <div style={{ textAlign: 'left' }}>
                <div className="badge badge-teal" style={{ marginBottom: '20px' }}>
                  <Sparkles style={{ width: '14px', height: '14px' }} /> Flagship Product Innovation
                </div>

                <h2 style={{ fontSize: 'clamp(2.1rem, 4vw, 2.9rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 18px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
                  nexARound <br />
                  <span className="text-gradient-teal">AI & AR Smart Tourism Companion</span>
                </h2>

                <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', lineHeight: 1.7, margin: '0 0 36px', maxWidth: '560px' }}>
                  An all-in-one mobile ecosystem that transforms any smartphone into a personal local guide. Experience real-time AR landmark camera scanning, Odyssey multi-day trip planning, Neva 24/7 travel concierge, Around You proximity radar, and interactive digital museum guides.
                </p>

                <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
                  <NavLink to="/app" className="btn-teal">
                    <Smartphone style={{ width: '18px', height: '18px' }} /> Explore Flagship App <ArrowRight style={{ width: '18px', height: '18px' }} />
                  </NavLink>
                </div>
              </div>

              {/* Module Highlights Grid */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '16px' }}>
                {[
                  { title: 'Odyssey Plan', tag: 'Smart Itineraries' },
                  { title: 'AR Scanner', tag: 'Real-Time Camera' },
                  { title: 'Neva AI Chat', tag: '24/7 Concierge' },
                  { title: 'Around You', tag: 'Location Radar' },
                  { title: 'Museum Guide', tag: 'Exhibit Audio' },
                  { title: 'Travel Stories', tag: 'Community Feed' },
                ].map((mod, idx) => (
                  <div key={idx} style={{ background: '#ffffff', border: '1px solid rgba(0, 122, 124, 0.18)', borderRadius: 'var(--radius-md)', padding: '20px 20px', boxShadow: '0 4px 16px rgba(0, 122, 124, 0.04)' }}>
                    <div style={{ fontSize: '0.72rem', fontWeight: 700, color: 'var(--teal)', textTransform: 'uppercase', marginBottom: '4px', letterSpacing: '0.5px' }}>{mod.tag}</div>
                    <div style={{ fontSize: '0.98rem', fontWeight: 800, color: 'var(--navy)' }}>{mod.title}</div>
                  </div>
                ))}
              </div>

            </div>

          </div>

        </div>
      </section>

      {/* ═══ SERVICES GRID ═══ */}
      <section className="section-padding" style={{ background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: '64px', flexWrap: 'wrap', gap: '24px' }}>
            <div style={{ maxWidth: '600px', textAlign: 'left' }}>
              <div className="badge badge-blue" style={{ marginBottom: '18px' }}>Core Capabilities</div>
              <h2 style={{ fontSize: 'clamp(2.1rem, 3.8vw, 2.9rem)', fontWeight: 800, color: 'var(--navy)', margin: 0, lineHeight: 1.15, letterSpacing: '-0.025em' }}>
                Engineering <span className="text-gradient-blue">Excellence</span> Across Every Layer
              </h2>
            </div>
            <NavLink to="/services" className="btn-secondary" style={{ color: 'var(--navy)', borderColor: 'var(--border-color)', background: 'var(--bg-light)' }}>
              View All Services <ChevronRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-2">
            {services.map((s, i) => (
              <div key={i} className="service-page-card" style={{ textAlign: 'left' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px' }}>
                  <div style={{ width: '52px', height: '52px', borderRadius: '14px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    {s.icon}
                  </div>
                  <span style={{ fontSize: '1.8rem', fontWeight: 800, color: 'rgba(26, 86, 219, 0.15)', fontFamily: 'var(--font-mono)' }}>{s.num}</span>
                </div>
                <h3 style={{ fontSize: '1.3rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>{s.title}</h3>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>{s.desc}</p>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ SOLUTIONS LIST ═══ */}
      <section className="section-padding" style={{ background: 'var(--bg-light)' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 64px' }}>
            <div className="badge badge-orange" style={{ marginBottom: '18px' }}>Proven Solutions</div>
            <h2 style={{ fontSize: 'clamp(2.1rem, 3.8vw, 2.9rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
              Turnkey Digital <span className="text-gradient-orange">Platforms</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.65 }}>
              Specialized enterprise software systems designed to solve operational challenges at scale.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '28px' }} className="grid-2">
            {solutions.map((sol, i) => (
              <div key={i} className="service-page-card" style={{ padding: '40px 36px', textAlign: 'left' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '20px' }}>
                  <div style={{ width: '46px', height: '46px', borderRadius: '12px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    {sol.icon}
                  </div>
                  <div>
                    <span style={{ fontSize: '0.72rem', fontWeight: 700, color: 'var(--blue)', textTransform: 'uppercase', letterSpacing: '0.8px' }}>{sol.tag}</span>
                    <h3 style={{ fontSize: '1.25rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>{sol.title}</h3>
                  </div>
                </div>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 24px' }}>{sol.desc}</p>
                <NavLink to="/solutions" style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.88rem', fontWeight: 700, color: 'var(--blue)' }}>
                  Explore Solution <ArrowRight style={{ width: '15px', height: '15px' }} />
                </NavLink>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ INDUSTRIES WE SERVE ═══ */}
      <section className="section-padding" style={{ background: '#ffffff' }}>
        <div className="container">
          
          <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 64px' }}>
            <div className="badge badge-blue" style={{ marginBottom: '18px' }}>Domain Expertise</div>
            <h2 style={{ fontSize: 'clamp(2.1rem, 3.8vw, 2.9rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
              Industries We <span className="text-gradient-blue">Empower</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.65 }}>
              Delivering specialized domain knowledge and custom software engineering across key global sectors.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px' }} className="grid-2">
            {industries.map((ind, i) => (
              <div key={i} className="service-page-card" style={{ padding: '26px 22px', display: 'flex', alignItems: 'center', gap: '16px' }}>
                <div style={{ width: '42px', height: '42px', borderRadius: '12px', background: 'rgba(26, 86, 219, 0.08)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {ind.icon}
                </div>
                <div style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--navy)' }}>{ind.name}</div>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* ═══ CTA SECTION ═══ */}
      <section className="container" style={{ padding: '90px 40px 110px' }}>
        <div style={{ 
          padding: '68px 44px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(26,86,219,0.06) 0%, #ffffff 50%, rgba(232,119,34,0.06) 100%)', 
          border: '1px solid rgba(26,86,219,0.2)',
          borderRadius: 'var(--radius-lg)',
          boxShadow: 'var(--shadow-md)',
          maxWidth: '1000px',
          margin: '0 auto'
        }}>
          <div className="badge badge-orange" style={{ marginBottom: '20px' }}>Start Your Journey</div>
          <h2 style={{ fontSize: 'clamp(2.1rem, 4vw, 2.9rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 18px', lineHeight: 1.2 }}>
            Ready to Fast-Track Your Digital Growth?
          </h2>
          <p style={{ color: 'var(--text-secondary)', margin: '0 0 38px', fontSize: '1.08rem', maxWidth: '620px', marginLeft: 'auto', marginRight: 'auto', lineHeight: 1.7 }}>
            Connect with our engineering leadership to discuss your product roadmap, custom software builds, or ERPNext deployment.
          </p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/contact" className="btn-primary">
              Schedule Technical Consultation <ArrowRight style={{ width: '18px', height: '18px' }} />
            </NavLink>
            <NavLink to="/solutions" className="btn-secondary" style={{ color: 'var(--navy)', borderColor: 'var(--border-color)', background: 'var(--bg-light)' }}>
              Explore All Solutions
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
