import { 
  Compass, Shield, Cpu, Users, Eye, Target, 
  Settings, ArrowRight, ShieldCheck, Zap 
} from 'lucide-react';

export default function About() {
  const values = [
    { title: 'End-to-end', desc: 'Discovery to delivery, one accountable team managing your entire product cycle.' },
    { title: 'Secure', desc: 'Security and privacy engineered in from day one across frontend and backend layers.' },
    { title: 'Scalable', desc: 'Software architectures designed to support high transaction volumes and business growth.' },
    { title: 'Quality First', desc: 'Code audits, unit testing, and automated quality assurance built into our process.' },
    { title: 'Client Focused', desc: 'Transparent, collaborative partnerships focused on delivering measurable outcomes.' }
  ];

  const expertises = [
    { title: 'Management & Advisory', desc: 'Strategy and IT advisory leadership guiding every software engagement.' },
    { title: 'Project Coordination', desc: 'Agile steering, business analysis, and dedicated client milestones.' },
    { title: 'Architecture & Security', desc: 'System blueprints and cybersecurity guidelines built into every layer.' },
    { title: 'Full Stack Development', desc: 'Custom engineering in Python (Flask/Django), PHP, and Node.js.' },
    { title: 'Frontend & UI/UX', desc: 'Human-centred design designed in Figma and implemented in React, Next.js, and Tailwind.' },
    { title: 'Mobile Development', desc: 'Native Android and iOS engineering alongside Flutter and React Native.' },
    { title: 'DevOps & Cloud', desc: 'CI/CD pipeline configuration, container orchestration, and server administration.' },
    { title: 'Quality Assurance', desc: 'Manual and automated testing frameworks across every build cycle.' },
    { title: 'Database Management', desc: 'Relational database scaling and indexing in PostgreSQL, MySQL, and MongoDB.' }
  ];

  const techStack = {
    languages: ['Python', 'JavaScript', 'TypeScript', 'PHP', 'Java', 'HTML/CSS'],
    frontend: ['Next.js', 'React.js', 'Angular', 'Vue.js', 'Tailwind CSS'],
    backend: ['Node.js', 'Django', 'Flask', 'FastAPI', 'Express.js'],
    mobile: ['Flutter', 'React Native', 'Android Native', 'iOS Native'],
    databases: ['MySQL', 'PostgreSQL', 'MongoDB', 'Redis', 'Firebase'],
    cloudDevops: ['AWS', 'Azure', 'Docker', 'Kubernetes', 'GitHub Actions'],
    blockchain: ['Ethereum', 'Solana', 'Hyperledger', 'Polygon', 'Smart Contracts'],
    aiData: ['TensorFlow', 'PyTorch', 'scikit-learn', 'Pandas', 'NumPy']
  };

  return (
    <div style={{ paddingBottom: '80px' }}>
      
      {/* Header */}
      <section style={{ textAlign: 'center', maxWidth: '700px', margin: '0 auto', padding: '110px 24px 0' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 20px' }}>Technology Expertise</div>
        <h1 style={{ fontSize: 'clamp(2rem, 4.5vw, 2.8rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15 }}>
          Expertise-driven Delivery & <br />
          <span className="text-gradient-blue">Team Excellence</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', lineHeight: 1.7, margin: 0 }}>
          NexARound Technologies is a Sri Lankan-based software engineering firm delivering next-generation digital solutions globally.
        </p>
      </section>

      {/* Engineering with Purpose / values */}
      <section className="container" style={{ paddingTop: '80px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div className="glass-card" style={{ padding: '48px 40px', background: 'linear-gradient(180deg, rgba(26,86,219,0.03) 0%, #fff 100%)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '32px', textAlign: 'left' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '10px', background: 'rgba(26,86,219,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Target className="w-6 h-6" style={{ color: 'var(--blue)' }} />
              </div>
              <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Engineering with Purpose</h2>
            </div>
            
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '16px' }} className="grid-2">
              {values.map((v, i) => (
                <div key={i} style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <ShieldCheck className="w-4 h-4" style={{ color: 'var(--orange)', flexShrink: 0 }} />
                    <span style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)' }}>{v.title}</span>
                  </div>
                  <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>{v.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Tech Expertise Grid */}
      <section className="container" style={{ paddingTop: '80px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div style={{ textAlign: 'center', maxWidth: '600px', margin: '0 auto 48px' }}>
          <div className="badge badge-orange" style={{ marginBottom: '14px' }}>Capabilities</div>
          <h2 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
            A comprehensive, cross-functional tech force
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', margin: 0 }}>
            At the helm of our operations is a visionary team orchestration backing Strategy, Architecture, Development, and Quality.
          </p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '20px' }} className="grid-2">
          {expertises.map((e, i) => (
            <div key={i} className="glass-card" style={{ padding: '28px 24px', textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '12px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <span style={{
                  width: '28px', height: '28px', borderRadius: '50%',
                  background: 'rgba(26,86,219,0.08)', color: 'var(--blue)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: '0.75rem', fontWeight: 800
                }}>{i + 1}</span>
                <h3 style={{ fontSize: '0.95rem', fontWeight: 700, color: 'var(--navy)', margin: 0 }}>{e.title}</h3>
              </div>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>{e.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Engagement Process */}
      <section style={{ marginTop: '80px', background: 'var(--bg-light)', padding: '80px 0' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          <div style={{ textAlign: 'center', maxWidth: '600px', margin: '0 auto 48px' }}>
            <div className="badge badge-blue" style={{ marginBottom: '14px' }}>Our Process</div>
            <h2 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
              From idea to impact
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', margin: 0 }}>
              A proven, agile approach that ensures clarity, quality, and on-time delivery.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '16px' }} className="grid-2">
            {[
              { num: '01', title: 'DISCOVER', desc: 'Understand your goals, challenges, and opportunities.' },
              { num: '02', title: 'PLAN', desc: 'Action roadmap, scope, architecture and success metrics.' },
              { num: '03', title: 'BUILD', desc: 'Agile development with continuous collaboration.' },
              { num: '04', title: 'TEST & VALIDATE', desc: 'Rigorous testing to ensure quality, security and performance.' },
              { num: '05', title: 'DEPLOY & SUPPORT', desc: 'Seamless deployment and ongoing support for long-term success.' }
            ].map((p, i) => (
              <div key={i} className="glass-card" style={{ padding: '24px 20px', background: '#fff', textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div style={{ fontSize: '1.25rem', fontWeight: 900, color: 'var(--blue)', opacity: 0.8, fontFamily: 'var(--font-mono)' }}>{p.num}</div>
                <div style={{ fontSize: '0.85rem', fontWeight: 700, color: 'var(--navy)' }}>{p.title}</div>
                <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.5, margin: 0 }}>{p.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Tech Stack we use */}
      <section className="container" style={{ paddingTop: '80px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div style={{ textAlign: 'center', maxWidth: '600px', margin: '0 auto 48px' }}>
          <div className="badge badge-orange" style={{ marginBottom: '14px' }}>Technologies We Use</div>
          <h2 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
            Our full stack capabilities
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', margin: 0 }}>
            We work with standard technologies across frontend, backend, databases, cloud, and AI.
          </p>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px' }} className="grid-2">
          {Object.entries(techStack).map(([category, items], i) => (
            <div key={i} className="glass-card" style={{ padding: '24px 20px', textAlign: 'left' }}>
              <div style={{ fontSize: '0.75rem', fontFamily: 'var(--font-mono)', fontWeight: 700, color: 'var(--blue)', textTransform: 'uppercase', marginBottom: '14px', letterSpacing: '0.5px' }}>
                {category.replace(/([A-Z])/g, ' $1').trim()}
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                {items.map((item, idx) => (
                  <span key={idx} className="badge" style={{ fontSize: '0.68rem', padding: '4px 8px', textTransform: 'none', letterSpacing: 'normal' }}>
                    {item}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>
      </section>

    </div>
  );
}
