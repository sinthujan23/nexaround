import { 
  Repeat, Code2, Cloud, BrainCircuit, Palette, ShieldCheck, 
  Users, Wallet, Clock, ArrowRight, Sparkles, CheckCircle2, ChevronRight, Zap, Layers, Cpu
} from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function Services() {
  const models = [
    { 
      icon: <Users style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, 
      title: 'Dedicated Team', 
      tag: 'Exclusive Talent',
      desc: 'A dedicated engineering team that works exclusively on your project as an integrated extension of your company.' 
    },
    { 
      icon: <Wallet style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, 
      title: 'Fixed Price', 
      tag: 'Predictable Scope',
      desc: 'Well-defined scope, timeline, and deliverables at a fixed price for predictable timelines and budget certainty.' 
    },
    { 
      icon: <Clock style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, 
      title: 'Time & Material', 
      tag: 'Agile Flexibility',
      desc: 'Flexible engagement based on dedicated hourly resources and changing project requirements as your business grows.' 
    },
    { 
      icon: <Repeat style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />, 
      title: 'Build-Operate-Transfer', 
      tag: 'Turnkey Transfer',
      desc: 'We build and operate the solution, then transfer full ownership, IP, and complete operational knowledge to your team.' 
    }
  ];

  return (
    <div style={{ paddingBottom: '80px' }}>
      
      {/* Header Section */}
      <section style={{ textAlign: 'center', maxWidth: '850px', margin: '0 auto', padding: '120px 24px 48px', position: 'relative' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 20px', display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
          <Sparkles style={{ width: '13px', height: '13px' }} /> Enterprise Capabilities
        </div>
        <h1 style={{ fontSize: 'clamp(2.4rem, 5.2vw, 3.6rem)', fontWeight: 900, color: 'var(--navy)', margin: '0 0 20px', lineHeight: 1.1, letterSpacing: '-0.03em' }}>
          Services Engineered for <br />
          <span className="text-gradient-blue">High-Scale Enterprise</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.15rem', lineHeight: 1.7, margin: 0, maxWidth: '700px', marginLeft: 'auto', marginRight: 'auto' }}>
          We design, engineer, and deploy future-proof digital architectures. End-to-end capabilities tailored for ambitious global organizations.
        </p>
      </section>

      {/* ═══ BENTO BOX GRID ═══ */}
      <section className="container" style={{ padding: '0 24px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(12, 1fr)', gap: '24px' }}>
          
          {/* BENTO 1: Digital Transformation (7 Columns - Dark Glass Highlight) */}
          <div className="bento-card-dark" style={{ gridColumn: 'span 7' }}>
            <div style={{ position: 'absolute', top: '-10%', right: '-10%', width: '300px', height: '300px', borderRadius: '50%', background: 'radial-gradient(circle, rgba(26,86,219,0.3) 0%, rgba(10,22,40,0) 70%)', pointerEvents: 'none' }} />

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px', position: 'relative', zIndex: 2 }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', fontSize: '0.75rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', background: 'rgba(232, 119, 34, 0.1)', padding: '5px 12px', borderRadius: '9999px', border: '1px solid rgba(232, 119, 34, 0.2)' }}>
                <Zap style={{ width: '13px', height: '13px' }} /> Core Transformation
              </div>
              <span style={{ fontSize: '2.5rem', fontWeight: 900, color: 'rgba(255, 255, 255, 0.15)', fontFamily: 'var(--font-mono)', lineHeight: 1 }}>01</span>
            </div>

            <h3 style={{ fontSize: '1.5rem', fontWeight: 800, color: '#ffffff', margin: '0 0 12px', position: 'relative', zIndex: 2 }}>
              Digital Transformation
            </h3>
            
            <p style={{ fontSize: '0.95rem', color: 'rgba(255, 255, 255, 0.75)', lineHeight: 1.7, margin: '0 0 28px', maxWidth: '520px', position: 'relative', zIndex: 2 }}>
              Reimagine operations end-to-end with modern, connected systems and clear digital roadmaps. Transition legacy software into intelligent B2B cloud architectures.
            </p>

            {/* Architecture Flow Visual Pill */}
            <div style={{ background: 'rgba(255, 255, 255, 0.04)', border: '1px solid rgba(255, 255, 255, 0.08)', borderRadius: '16px', padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px', flexWrap: 'wrap', position: 'relative', zIndex: 2 }}>
              {['Legacy Software', 'API Gateway', 'Cloud Core', 'AI Intelligence'].map((step, idx) => (
                <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{ fontSize: '0.78rem', fontWeight: 700, color: idx === 3 ? 'var(--blue-light)' : '#ffffff' }}>
                    {step}
                  </span>
                  {idx < 3 && <ChevronRight style={{ width: '14px', height: '14px', color: 'rgba(255,255,255,0.3)' }} />}
                </div>
              ))}
            </div>
          </div>

          {/* BENTO 2: Software Engineering (5 Columns - White Glass Card) */}
          <div className="bento-card" style={{ gridColumn: 'span 5', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px' }}>
                <div style={{ width: '52px', height: '52px', borderRadius: '14px', background: 'linear-gradient(135deg, rgba(26,86,219,0.1), rgba(26,86,219,0.03))', border: '1px solid rgba(26,86,219,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Code2 style={{ width: '26px', height: '26px', color: 'var(--blue)' }} />
                </div>
                <span style={{ fontSize: '2.5rem', fontWeight: 900, color: 'rgba(26,86,219,0.12)', fontFamily: 'var(--font-mono)', lineHeight: 1 }}>02</span>
              </div>

              <div style={{ fontSize: '0.78rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', letterSpacing: '0.8px', marginBottom: '8px' }}>
                Full-Stack Excellence
              </div>

              <h3 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
                Software Engineering
              </h3>

              <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 24px' }}>
                Custom, full-stack development delivered with quality and scalability built in. Modern web, mobile, and backend frameworks.
              </p>
            </div>

            {/* Tech Badges */}
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
              {['React.js', 'Node.js', 'Python', 'Flutter', 'PostgreSQL'].map((t, idx) => (
                <span key={idx} style={{ fontSize: '0.74rem', fontWeight: 600, color: 'var(--navy)', background: 'rgba(26,86,219,0.06)', border: '1px solid rgba(26,86,219,0.1)', padding: '5px 12px', borderRadius: '8px' }}>
                  {t}
                </span>
              ))}
            </div>
          </div>

          {/* BENTO 3: AI, ML & Data (4 Columns) */}
          <div className="bento-card" style={{ gridColumn: 'span 4' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'linear-gradient(135deg, rgba(26,86,219,0.1), rgba(232,119,34,0.05))', border: '1px solid rgba(26,86,219,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <BrainCircuit style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />
              </div>
              <span style={{ fontSize: '2.2rem', fontWeight: 900, color: 'rgba(26,86,219,0.12)', fontFamily: 'var(--font-mono)', lineHeight: 1 }}>03</span>
            </div>

            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 10px' }}>
              AI, ML & Data
            </h3>

            <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 20px' }}>
              Predictive models, automated document processing (LLMs), and live data pipelines that integrate your ERPs.
            </p>

            <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
              {['Custom LLMs', 'Analytics', 'PyTorch'].map((t, idx) => (
                <span key={idx} style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--blue)', background: 'rgba(26,86,219,0.06)', padding: '4px 10px', borderRadius: '6px' }}>{t}</span>
              ))}
            </div>
          </div>

          {/* BENTO 4: Cloud Implementation (4 Columns) */}
          <div className="bento-card" style={{ gridColumn: 'span 4' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'linear-gradient(135deg, rgba(26,86,219,0.1), rgba(26,86,219,0.03))', border: '1px solid rgba(26,86,219,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Cloud style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />
              </div>
              <span style={{ fontSize: '2.2rem', fontWeight: 900, color: 'rgba(26,86,219,0.12)', fontFamily: 'var(--font-mono)', lineHeight: 1 }}>04</span>
            </div>

            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 10px' }}>
              Cloud Implementation
            </h3>

            <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 20px' }}>
              Cloud-native architectures, DevOps CI/CD pipelines, automated security checks, and zero downtime deployments.
            </p>

            <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
              {['AWS & Azure', 'Docker/K8s', 'CI/CD'].map((t, idx) => (
                <span key={idx} style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--blue)', background: 'rgba(26,86,219,0.06)', padding: '4px 10px', borderRadius: '6px' }}>{t}</span>
              ))}
            </div>
          </div>

          {/* BENTO 5: UI / UX Design (4 Columns) */}
          <div className="bento-card" style={{ gridColumn: 'span 4' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'linear-gradient(135deg, rgba(26,86,219,0.1), rgba(232,119,34,0.05))', border: '1px solid rgba(26,86,219,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Palette style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />
              </div>
              <span style={{ fontSize: '2.2rem', fontWeight: 900, color: 'rgba(26,86,219,0.12)', fontFamily: 'var(--font-mono)', lineHeight: 1 }}>05</span>
            </div>

            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 10px' }}>
              UI / UX Design
            </h3>

            <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: '0 0 20px' }}>
              Human-centred interfaces built for maximum user adoption. Figma design systems and interactive wireframes.
            </p>

            <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
              {['Design Systems', 'Prototypes', 'Figma'].map((t, idx) => (
                <span key={idx} style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--blue)', background: 'rgba(26,86,219,0.06)', padding: '4px 10px', borderRadius: '6px' }}>{t}</span>
              ))}
            </div>
          </div>

          {/* BENTO 6: Quality & Automation (12 Columns Full Width Security Banner) */}
          <div className="bento-card-dark" style={{ gridColumn: 'span 12', padding: '40px 48px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '32px' }}>
              <div style={{ maxWidth: '580px' }}>
                <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontSize: '0.78rem', fontWeight: 700, color: '#10b981', background: 'rgba(16, 185, 129, 0.1)', padding: '5px 14px', borderRadius: '9999px', border: '1px solid rgba(16, 185, 129, 0.25)', marginBottom: '16px' }}>
                  <ShieldCheck style={{ width: '15px', height: '15px' }} /> Automated Security & QA Assurance
                </div>
                <h3 style={{ fontSize: '1.6rem', fontWeight: 800, color: '#ffffff', margin: '0 0 10px', letterSpacing: '-0.02em' }}>
                  Quality & Continuous Automation (06)
                </h3>
                <p style={{ fontSize: '0.95rem', color: 'rgba(255,255,255,0.7)', lineHeight: 1.7, margin: 0 }}>
                  Automated testing integrated directly into your build cycles to identify bottlenecks, perform security scans, and ensure zero-defect software releases.
                </p>
              </div>

              {/* Security Checkmarks Grid */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '14px', background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', borderRadius: '16px', padding: '20px 24px' }}>
                {[
                  'Automated Integration QA',
                  'Penetration Security Scans',
                  'High-Load Stress Testing',
                  'Continuous Vulnerability Verification'
                ].map((check, idx) => (
                  <div key={idx} style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '0.82rem', color: '#ffffff', fontWeight: 600 }}>
                    <CheckCircle2 style={{ width: '16px', height: '16px', color: '#10b981', flexShrink: 0 }} />
                    {check}
                  </div>
                ))}
              </div>
            </div>
          </div>

        </div>
      </section>

      {/* Engagement Models Section */}
      <section style={{ marginTop: '100px', background: 'var(--bg-light)', padding: '100px 0', position: 'relative', overflow: 'hidden' }}>
        
        {/* Ambient Glow */}
        <div style={{ position: 'absolute', top: '15%', right: '-5%', width: '400px', height: '400px', borderRadius: '50%', background: 'radial-gradient(circle, rgba(232,119,34,0.06) 0%, rgba(255,255,255,0) 70%)', pointerEvents: 'none' }} />

        <div className="container" style={{ padding: '0 24px', position: 'relative', zIndex: 2 }}>
          
          <div style={{ textAlign: 'center', maxWidth: '650px', margin: '0 auto 56px' }}>
            <div className="badge badge-orange" style={{ marginBottom: '16px', display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
              <Sparkles style={{ width: '13px', height: '13px' }} /> Partnership Frameworks
            </div>
            <h2 style={{ fontSize: 'clamp(2rem, 3.8vw, 2.8rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 14px', lineHeight: 1.2, letterSpacing: '-0.02em' }}>
              Flexible Engagement Models. <br />
              <span className="text-gradient-orange">Maximum Value.</span>
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '1.02rem', margin: 0, lineHeight: 1.6 }}>
              Choose the engagement model that best fits your operational needs, project scope, and growth velocity.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px' }} className="grid-2">
            {models.map((m, i) => (
              <div key={i} className="service-page-card" style={{ padding: '30px 24px' }}>
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                    <div style={{
                      width: '48px', height: '48px', borderRadius: '12px',
                      background: 'linear-gradient(135deg, rgba(26, 86, 219, 0.1) 0%, rgba(232, 119, 34, 0.05) 100%)', 
                      border: '1px solid rgba(26, 86, 219, 0.15)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center'
                    }}>
                      {m.icon}
                    </div>

                    <span style={{ fontSize: '0.7rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', background: 'rgba(232, 119, 34, 0.08)', padding: '4px 10px', borderRadius: '6px', border: '1px solid rgba(232, 119, 34, 0.15)' }}>
                      {m.tag}
                    </span>
                  </div>

                  <h3 style={{ fontSize: '1.15rem', fontWeight: 700, color: 'var(--navy)', margin: '0 0 10px', lineHeight: 1.3 }}>
                    {m.title}
                  </h3>

                  <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
                    {m.desc}
                  </p>
                </div>
              </div>
            ))}
          </div>

        </div>
      </section>

      {/* CTA Section */}
      <section className="container" style={{ padding: '100px 24px 0' }}>
        <div style={{ 
          padding: '60px 40px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(26,86,219,0.06) 0%, #ffffff 50%, rgba(232,119,34,0.06) 100%)', 
          border: '1px solid rgba(26,86,219,0.2)',
          borderRadius: '24px',
          boxShadow: '0 10px 40px -10px rgba(10,22,40,0.06)',
          maxWidth: '960px',
          margin: '0 auto'
        }}>
          <div className="badge badge-blue" style={{ marginBottom: '16px', display: 'inline-flex', alignItems: 'center', gap: '6px' }}>
            <Sparkles style={{ width: '13px', height: '13px' }} /> Consult Our Team
          </div>

          <h2 style={{ fontSize: 'clamp(1.8rem, 3.5vw, 2.5rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 14px', lineHeight: 1.2 }}>
            Ready to Accelerate Your Digital Growth?
          </h2>

          <p style={{ color: 'var(--text-secondary)', margin: '0 0 32px', fontSize: '1.02rem', maxWidth: '560px', marginLeft: 'auto', marginRight: 'auto', lineHeight: 1.6 }}>
            Discuss your custom software engineering, cloud migration, or AI data requirements with our senior architects.
          </p>

          <div style={{ display: 'flex', justifyContent: 'center', gap: '16px', flexWrap: 'wrap' }}>
            <NavLink to="/contact" className="btn-primary" style={{ padding: '13px 28px', fontSize: '0.92rem', display: 'inline-flex', alignItems: 'center', gap: '8px' }}>
              Get in Touch <ArrowRight style={{ width: '16px', height: '16px' }} />
            </NavLink>
            <NavLink to="/solutions" className="btn-secondary" style={{ padding: '13px 28px', fontSize: '0.92rem', display: 'inline-flex', alignItems: 'center' }}>
              View Flagship Solutions
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
