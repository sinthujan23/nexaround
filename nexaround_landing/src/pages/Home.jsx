import { NavLink } from 'react-router-dom';
import {
  Code2, BrainCircuit, Blocks, Cloud, ArrowRight, Sparkles,
  Repeat, Monitor, Cpu, Palette, ShieldCheck,
  Building2, GraduationCap, Briefcase, Factory, HardHat,
  Radio, Zap, Headphones, ChevronRight
} from 'lucide-react';

export default function Home() {
  const services = [
    { num: '01', icon: <Repeat style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Digital Transformation', desc: 'Reimagine operations end-to-end with modern, connected systems and clear roadmaps.' },
    { num: '02', icon: <Code2 style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Software Engineering', desc: 'Custom, full-stack development delivered with quality and scalability built in.' },
    { num: '03', icon: <Cloud style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Cloud Implementation', desc: 'Cloud-native architecture, DevOps, and secure infrastructure that grows with you.' },
    { num: '04', icon: <BrainCircuit style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'AI, ML & Data', desc: 'Predictive models, automation, and data pipelines that turn information into decisions.' },
    { num: '05', icon: <Palette style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'UI / UX Design', desc: 'Human-centred interfaces that are clear to use and a pleasure to look at.' },
    { num: '06', icon: <ShieldCheck style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Quality & Automation', desc: 'Automated testing and quality engineering so every release ships with confidence.' },
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
    { icon: <Monitor style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'ERPNext & Business Solutions', desc: 'End-to-end ERPNext implementation, customization and support to streamline operations.' },
    { icon: <BrainCircuit style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'AI, ML & Data Solutions', desc: 'Intelligent solutions using machine learning, predictive analytics, and data engineering.' },
    { icon: <Blocks style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Blockchain & Web3 Solutions', desc: 'Secure, decentralized applications, smart contracts, and tokenization platforms.' },
    { icon: <Cloud style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, title: 'Cloud & DevOps Engineering', desc: 'Scalable cloud infrastructure, CI/CD pipelines, and DevOps automation at scale.' },
  ];

  return (
    <div>
      
      {/* ═══ HERO ═══ */}
      <section className="dark-section" style={{ position: 'relative', minHeight: '100vh', display: 'flex', alignItems: 'flex-start', overflow: 'hidden', background: 'var(--navy)', padding: '160px 0 60px' }}>
        
        {/* Background Video */}
        <video 
          autoPlay 
          loop 
          muted 
          playsInline 
          style={{ 
            position: 'absolute', 
            top: 0, 
            left: 0, 
            width: '100%', 
            height: '100%', 
            objectFit: 'cover', 
            zIndex: 1, 
            pointerEvents: 'none', 
            opacity: 0.28
          }}
        >
          <source src="/hero_bg.mp4" type="video/mp4" />
        </video>

        <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, rgba(10,22,40,0.4), rgba(10,22,40,0.75))', zIndex: 1, pointerEvents: 'none' }} />

        <div className="container" style={{ padding: '0 24px', position: 'relative', zIndex: 2 }}>
          <div style={{ maxWidth: '820px' }}>
            
            {/* Pillar Icons Bar */}
            <div style={{ display: 'flex', gap: '24px', marginBottom: '40px', flexWrap: 'wrap' }}>
              {[
                { icon: <Code2 style={{ width: '20px', height: '20px', color: 'var(--blue-light)' }} />, label: 'Full-Stack Engineering' },
                { icon: <BrainCircuit style={{ width: '20px', height: '20px', color: 'var(--blue-light)' }} />, label: 'AI & Data' },
                { icon: <Blocks style={{ width: '20px', height: '20px', color: 'var(--blue-light)' }} />, label: 'Blockchain' },
                { icon: <Cloud style={{ width: '20px', height: '20px', color: 'var(--blue-light)' }} />, label: 'Cloud & ERP' },
              ].map((p, i) => (
                <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '6px', fontSize: '0.68rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.5px', color: 'rgba(255, 255, 255, 0.6)' }}>
                  {p.icon}
                  {p.label}
                </div>
              ))}
            </div>

            <h1 style={{ fontSize: 'clamp(3rem, 6vw, 4.4rem)', fontWeight: 900, color: '#ffffff', lineHeight: 1.1, margin: '0 0 24px', letterSpacing: '-0.03em' }}>
              NexARound{' '}
              <span className="text-gradient-blue">Technologies</span>
            </h1>

            <p style={{ fontSize: '1.6rem', fontWeight: 600, color: '#ffffff', margin: '0 0 20px', lineHeight: 1.4 }}>
              Full-stack engineering to fast-track your growth.
            </p>

            <p style={{ fontSize: '1.15rem', color: 'rgba(255, 255, 255, 0.75)', margin: '0 0 40px', lineHeight: 1.7, maxWidth: '700px' }}>
              Tailored digital solutions for every sector. We help businesses, institutions, and 
              communities design, build, and scale intelligent software systems — across Sri Lanka and beyond.
            </p>

            <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap' }}>
              <NavLink to="/solutions" className="btn-primary" style={{ padding: '12px 26px', fontSize: '0.9rem' }}>
                Explore Solutions <ArrowRight style={{ width: '18px', height: '18px' }} />
              </NavLink>
              <NavLink to="/contact" className="btn-secondary" style={{ padding: '12px 26px', fontSize: '0.9rem', background: 'transparent', color: '#fff', borderColor: 'rgba(255, 255, 255, 0.3)' }}>
                Get in Touch
              </NavLink>
            </div>
          </div>
        </div>
      </section>

      {/* ═══ WHAT WE DO ═══ */}
      <section style={{ padding: '80px 0', background: 'var(--bg-light)' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          <div style={{ marginBottom: '48px' }}>
            <div className="badge badge-orange" style={{ marginBottom: '14px' }}>What We Do</div>
            <h2 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 10px' }}>
              Tailor-made software to accelerate performance
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', margin: 0, maxWidth: '650px' }}>
              that help businesses operate efficiently, grow faster, and lead confidently.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px' }} className="grid-3">
            {services.map((s, i) => (
              <div key={i} className="glass-card" style={{ padding: '28px 24px', textAlign: 'left', position: 'relative', overflow: 'hidden' }}>
                <div style={{ position: 'absolute', top: '-4px', right: '12px', fontSize: '3rem', fontWeight: 900, color: 'rgba(26,86,219,0.05)', fontFamily: 'var(--font-mono)', lineHeight: 1, pointerEvents: 'none' }}>{s.num}</div>
                <div style={{ width: '44px', height: '44px', borderRadius: '10px', background: 'rgba(26,86,219,0.08)', border: '1px solid rgba(26,86,219,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: '14px', position: 'relative', zIndex: 2 }}>
                  {s.icon}
                </div>
                <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--navy)', margin: '0 0 8px', position: 'relative', zIndex: 2 }}>{s.title}</h3>
                <p style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0, position: 'relative', zIndex: 2 }}>{s.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══ INDUSTRIES ═══ */}
      <section className="dark-section" style={{ padding: '64px 0' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          <h2 style={{ fontSize: '1.1rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '2px', color: '#fff', marginBottom: '36px', textAlign: 'center' }}>
            Industries We Serve
          </h2>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(8, 1fr)', gap: '16px', textAlign: 'center' }} className="grid-4">
            {industries.map((ind, i) => (
              <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '10px', padding: '16px 8px' }}>
                <div style={{ color: 'var(--blue-light)' }}>{ind.icon}</div>
                <span style={{ fontSize: '0.72rem', color: 'rgba(255,255,255,0.7)', fontWeight: 600, lineHeight: 1.3 }}>{ind.name}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══ FEATURED SOLUTIONS ═══ */}
      <section style={{ padding: '80px 0' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          <div style={{ marginBottom: '48px' }}>
            <div className="badge badge-blue" style={{ marginBottom: '14px' }}>Featured Solutions</div>
            <h2 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 10px' }}>
              Solutions that drive real <span className="text-gradient-orange">impact</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', margin: 0, maxWidth: '550px' }}>
              We build future-ready solutions that solve complex problems and create measurable value.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '20px' }} className="grid-2">
            {solutions.map((s, i) => (
              <div key={i} className="glass-card" style={{ padding: '32px 28px', textAlign: 'left', display: 'flex', gap: '18px', alignItems: 'flex-start' }}>
                <div style={{ width: '48px', height: '48px', borderRadius: '12px', background: 'rgba(26,86,219,0.08)', border: '1px solid rgba(26,86,219,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  {s.icon}
                </div>
                <div>
                  <h3 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', margin: '0 0 8px' }}>{s.title}</h3>
                  <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 12px' }}>{s.desc}</p>
                  <NavLink to="/solutions" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', fontSize: '0.8rem', fontWeight: 600, color: 'var(--blue)' }}>
                    Learn more <ChevronRight style={{ width: '14px', height: '14px' }} />
                  </NavLink>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ═══ CTA ═══ */}
      <section className="dark-section" style={{ padding: '64px 0' }}>
        <div className="container" style={{ padding: '0 24px', textAlign: 'center' }}>
          <h2 style={{ fontSize: '2rem', fontWeight: 800, color: '#fff', margin: '0 0 14px' }}>
            Let's build something <span className="text-gradient-orange">extraordinary</span> together.
          </h2>
          <p style={{ color: 'rgba(255,255,255,0.6)', fontSize: '1rem', margin: '0 0 28px', maxWidth: '500px', marginLeft: 'auto', marginRight: 'auto' }}>
            We are ready to turn your ideas into powerful digital solutions.
          </p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '14px', flexWrap: 'wrap' }}>
            <NavLink to="/contact" className="btn-orange">
              <Sparkles style={{ width: '16px', height: '16px' }} /> Get in Touch
            </NavLink>
            <NavLink to="/solutions" className="btn-secondary" style={{ background: 'transparent', color: '#fff', borderColor: 'rgba(255,255,255,0.2)' }}>
              View Solutions
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
