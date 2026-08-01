import { 
  Target, Cpu, GitCommit, CheckCircle2, ShieldCheck, 
  ArrowRight, Sparkles, Code2, Users, Layers, Lock, Award
} from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function About() {
  const values = [
    { title: 'Full Accountability', desc: 'End-to-end ownership from architecture to production SLA monitoring.' },
    { title: 'Security First', desc: 'Enterprise encryption, audited protocols, and strict data privacy compliance.' },
    { title: 'Built to Scale', desc: 'Architectures engineered for multi-region scale and high peak concurrency.' },
    { title: 'Rigorous QA', desc: 'Automated CI/CD security scans and regression testing on every build.' },
    { title: 'Transparent Partnership', desc: 'Direct collaboration with senior engineers, clear roadmaps, and agile delivery.' }
  ];

  const expertises = [
    { name: 'Software Architecture', desc: 'Microservices, event-driven design, and cloud-native systems.' },
    { name: 'Full-Stack Development', desc: 'Modern web, mobile, and backend microservice development.' },
    { name: 'Data & Machine Learning', desc: 'ETL pipelines, predictive models, and document processing LLMs.' },
    { name: 'DevOps & Cloud Ops', desc: 'Terraform IaC, Kubernetes orchestration, and zero-downtime CI/CD.' },
    { name: 'Web3 & Smart Contracts', desc: 'Audited Ethereum, Polygon & Solana smart contract architecture.' },
    { name: 'UI / UX Design', desc: 'User-centered design systems, interactive prototypes, and modern UI.' },
    { name: 'Quality Assurance', desc: 'End-to-end automated testing, load testing, and security auditing.' },
    { name: 'ERP Implementation', desc: 'Custom ERPNext modules, workflow automation, and enterprise support.' },
    { name: 'Mobile Engineering', desc: 'High-performance Flutter apps with AR camera vision and geolocation.' },
  ];

  const stages = [
    { num: '01', title: 'Discovery & Requirements', desc: 'Deep dive into operational workflows, tech debt, and strategic objectives.' },
    { num: '02', title: 'Architecture & Design', desc: 'Detailed system blueprints, API schemas, security models, and UI wireframes.' },
    { num: '03', title: 'Agile Engineering', desc: 'Iterative sprint development with continuous client feedback and code reviews.' },
    { num: '04', title: 'Automated QA & Testing', desc: 'Load testing, vulnerability scans, and user acceptance testing (UAT).' },
    { num: '05', title: 'Deployment & Support', desc: 'Zero-downtime cloud release, continuous monitoring, and ongoing SLA maintenance.' },
  ];

  return (
    <div style={{ paddingBottom: '100px' }}>
      
      {/* Header Section with Office Showcase Image */}
      <section style={{ textAlign: 'center', maxWidth: '1020px', margin: '0 auto', padding: '160px 24px 64px', position: 'relative' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 22px' }}>
          <Sparkles style={{ width: '14px', height: '14px' }} /> Engineering Excellence
        </div>
        <h1 style={{ fontSize: 'clamp(2.5rem, 5vw, 3.6rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 20px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
          Technical Delivery & <br />
          <span className="text-gradient-blue">Team Excellence</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.12rem', lineHeight: 1.7, margin: '0 auto 48px', maxWidth: '720px' }}>
          NexARound Technologies is a premier software engineering firm delivering next-generation digital solutions globally across Sri Lanka and worldwide.
        </p>

        {/* Corporate Office Image Showcase */}
        <div style={{ position: 'relative', borderRadius: 'var(--radius-lg)', overflow: 'hidden', border: '1px solid rgba(26,86,219,0.2)', boxShadow: 'var(--shadow-lg)' }}>
          <img 
            src="/about_office.png" 
            alt="NexARound Technologies Engineering HQ" 
            style={{ width: '100%', height: '400px', objectFit: 'cover' }} 
          />
          <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '28px 36px', background: 'linear-gradient(to top, rgba(10,22,40,0.92) 0%, rgba(10,22,40,0) 100%)', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', color: '#ffffff' }}>
            <div style={{ textAlign: 'left' }}>
              <div style={{ fontSize: '0.75rem', fontWeight: 700, color: '#60a5fa', textTransform: 'uppercase', letterSpacing: '1px' }}>Global Delivery Center</div>
              <div style={{ fontSize: '1.3rem', fontWeight: 800 }}>Full-Stack Software Engineering HQ</div>
            </div>
            <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'rgba(255,255,255,0.9)', background: 'rgba(255,255,255,0.15)', padding: '8px 18px', borderRadius: '9999px', backdropFilter: 'blur(12px)' }}>
              Sri Lanka & International Operations
            </div>
          </div>
        </div>
      </section>

      {/* Core Principles */}
      <section className="container" style={{ padding: '36px 40px 0' }}>
        <div className="service-page-card" style={{ padding: '52px 48px' }}>
          <div style={{ textAlign: 'left' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '36px' }}>
              <div style={{ width: '52px', height: '52px', borderRadius: '16px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Target style={{ width: '26px', height: '26px', color: 'var(--blue)' }} />
              </div>
              <div>
                <div style={{ fontSize: '0.78rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', letterSpacing: '1px' }}>Core Philosophy</div>
                <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Engineering with Purpose</h2>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '20px' }} className="grid-2">
              {values.map((v, i) => (
                <div key={i} style={{ padding: '24px 18px', background: 'rgba(26,86,219,0.03)', border: '1px solid rgba(26,86,219,0.08)', borderRadius: '14px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '10px' }}>
                    <ShieldCheck style={{ width: '18px', height: '18px', color: 'var(--orange)', flexShrink: 0 }} />
                    <div style={{ fontSize: '0.92rem', fontWeight: 700, color: 'var(--navy)' }}>{v.title}</div>
                  </div>
                  <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>{v.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Expertise Grid */}
      <section className="container" style={{ padding: '90px 40px 0' }}>
        <div style={{ textAlign: 'center', maxWidth: '680px', margin: '0 auto 64px' }}>
          <div className="badge badge-orange" style={{ marginBottom: '18px' }}>
            <Cpu style={{ width: '14px', height: '14px' }} /> Cross-Functional Capabilities
          </div>
          <h2 style={{ fontSize: 'clamp(2.1rem, 3.8vw, 2.9rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px' }}>
            A Comprehensive Tech Force
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', margin: 0, lineHeight: 1.65 }}>
            Our cross-functional teams integrate strategy, architecture, development, and quality assurance into one cohesive unit.
          </p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '28px' }} className="grid-2">
          {expertises.map((e, i) => (
            <div key={i} className="service-page-card" style={{ padding: '32px 28px', textAlign: 'left' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                <CheckCircle2 style={{ width: '18px', height: '18px', color: 'var(--blue)', flexShrink: 0 }} />
                <h3 style={{ fontSize: '1.15rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>{e.name}</h3>
              </div>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>{e.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Delivery Lifecycle */}
      <section className="container" style={{ padding: '90px 40px 0' }}>
        <div className="service-page-card" style={{ padding: '52px 48px', textAlign: 'left' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '14px', marginBottom: '40px' }}>
            <div style={{ width: '52px', height: '52px', borderRadius: '16px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <GitCommit style={{ width: '26px', height: '26px', color: 'var(--blue)' }} />
            </div>
            <div>
              <div style={{ fontSize: '0.78rem', fontWeight: 700, color: 'var(--blue)', textTransform: 'uppercase', letterSpacing: '1px' }}>Structured Workflow</div>
              <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>5-Stage Delivery Lifecycle</h2>
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '20px' }} className="grid-2">
            {stages.map((st, i) => (
              <div key={i} style={{ padding: '24px 18px', background: 'rgba(15, 23, 42, 0.03)', border: '1px solid rgba(15, 23, 42, 0.08)', borderRadius: '14px' }}>
                <div style={{ fontSize: '1.8rem', fontWeight: 800, color: 'var(--blue)', fontFamily: 'var(--font-mono)', marginBottom: '8px' }}>{st.num}</div>
                <div style={{ fontSize: '0.92rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '8px' }}>{st.title}</div>
                <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>{st.desc}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="container" style={{ padding: '90px 40px 0' }}>
        <div style={{ 
          padding: '64px 44px', 
          textAlign: 'center', 
          background: 'linear-gradient(135deg, rgba(26,86,219,0.06) 0%, #ffffff 50%, rgba(232,119,34,0.06) 100%)', 
          border: '1px solid rgba(26,86,219,0.2)',
          borderRadius: 'var(--radius-lg)',
          boxShadow: 'var(--shadow-md)',
          maxWidth: '1000px',
          margin: '0 auto'
        }}>
          <h2 style={{ fontSize: 'clamp(1.9rem, 3.5vw, 2.7rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px' }}>
            Partner with a World-Class Engineering Team
          </h2>
          <p style={{ color: 'var(--text-secondary)', margin: '0 0 36px', fontSize: '1.05rem', maxWidth: '600px', marginLeft: 'auto', marginRight: 'auto', lineHeight: 1.7 }}>
            Let us build the custom software architecture your business requires to scale.
          </p>
          <NavLink to="/contact" className="btn-primary">
            Get in Touch <ArrowRight style={{ width: '18px', height: '18px' }} />
          </NavLink>
        </div>
      </section>

    </div>
  );
}
