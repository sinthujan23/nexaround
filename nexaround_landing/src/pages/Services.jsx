import { 
  Repeat, Code2, Cloud, BrainCircuit, Palette, ShieldCheck, 
  Users, Wallet, Clock, ArrowRight 
} from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function Services() {
  const detailServices = [
    {
      num: '01',
      icon: <Repeat className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />,
      title: 'Digital Transformation',
      tagline: 'Modernize operations from the ground up.',
      desc: 'Reimagine operations end-to-end with modern, connected systems and clear roadmaps. We guide you through transitioning legacy software into intelligent B2B systems to make your business more efficient and cost-effective.'
    },
    {
      num: '02',
      icon: <Code2 className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />,
      title: 'Software Engineering',
      tagline: 'Scalable, custom solutions engineered for success.',
      desc: 'Get custom, full-stack development delivered with quality and scalability built in. We leverage modern web, mobile, and backend frameworks to build reliable applications tailored to your specific goals.'
    },
    {
      num: '03',
      icon: <Cloud className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />,
      title: 'Cloud Implementation',
      tagline: 'Secure infrastructure that scales with you.',
      desc: 'We design cloud-native architectures and configure DevOps CI/CD pipelines to ensure reliability, security, and automated deployments. Transition your systems to AWS or Azure smoothly.'
    },
    {
      num: '04',
      icon: <BrainCircuit className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />,
      title: 'AI, ML & Data',
      tagline: 'Turn your enterprise data into actionable decisions.',
      desc: 'Develop predictive models, automated document processing (LLMs), and live data pipelines that integrate your ERPs, databases, and APIs. We build custom intelligence systems designed for maximum ROI.'
    },
    {
      num: '05',
      icon: <Palette className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />,
      title: 'UI / UX Design',
      tagline: 'Human-centred interfaces built for conversion.',
      desc: 'Create beautiful, easy-to-use interfaces that are clear and a pleasure to look at. We design detailed prototypes, user flows, and wireframes focused on maximizing user adoption.'
    },
    {
      num: '06',
      icon: <ShieldCheck className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />,
      title: 'Quality & Automation',
      tagline: 'Ship every release with absolute confidence.',
      desc: 'Automated testing and QA engineering integrated directly into your build cycles. We identify bottlenecks and automate security checks to protect your applications.'
    }
  ];

  const models = [
    { icon: <Users className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />, title: 'Dedicated Team', desc: 'A dedicated team that works exclusively on your project as an extension of your company.' },
    { icon: <Wallet className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />, title: 'Fixed Price', desc: 'Well-defined scope, timeline, and deliverables at a fixed price for predictable results.' },
    { icon: <Clock className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />, title: 'Time & Material', desc: 'Flexible engagement based on hourly resources and changing project requirements.' },
    { icon: <Repeat className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />, title: 'Build-Operate-Transfer', desc: 'We build and operate the solution, then transfer full ownership and knowledge to your team.' }
  ];

  return (
    <div style={{ paddingBottom: '80px' }}>
      
      {/* Header */}
      <section style={{ paddingTop: '64px', textAlign: 'center', maxWidth: '700px', margin: '0 auto', padding: '64px 24px 0' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 20px' }}>Enterprise Services</div>
        <h1 style={{ fontSize: 'clamp(2rem, 4.5vw, 2.8rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15 }}>
          Engineering Services to <br />
          <span className="text-gradient-blue">Accelerate Performance</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', lineHeight: 1.7, margin: 0 }}>
          Tailored B2B digital solutions. We help businesses design, build, and scale intelligent software systems.
        </p>
      </section>

      {/* Detailed Services list */}
      <section className="container" style={{ padding: '64px 24px 0' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr', gap: '40px' }}>
          {detailServices.map((s, i) => (
            <div key={i} className="glass-card" style={{ padding: '40px', display: 'flex', gap: '32px', alignItems: 'flex-start', flexWrap: 'wrap' }}>
              <div style={{
                width: '60px', height: '60px', borderRadius: '12px',
                background: 'rgba(26,86,219,0.08)', border: '1px solid rgba(26,86,219,0.12)',
                display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0
              }}>
                {s.icon}
              </div>
              <div style={{ flex: 1, minWidth: '280px', textAlign: 'left' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <h3 style={{ fontSize: '1.25rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>
                    {s.title}
                  </h3>
                  <span style={{ fontSize: '1.2rem', fontWeight: 900, color: 'rgba(26,86,219,0.15)', fontFamily: 'var(--font-mono)' }}>{s.num}</span>
                </div>
                <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--orange)', marginTop: '4px', marginBottom: '12px' }}>
                  {s.tagline}
                </div>
                <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                  {s.desc}
                </p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Engagement Models */}
      <section style={{ marginTop: '80px', background: 'var(--bg-light)', padding: '80px 0' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          <div style={{ textAlign: 'center', maxWidth: '600px', margin: '0 auto 48px' }}>
            <div className="badge badge-orange" style={{ marginBottom: '14px' }}>Engagement Models</div>
            <h2 style={{ fontSize: '2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
              Flexible models. Maximum value.
            </h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.95rem', margin: 0 }}>
              Choose the engagement model that fits your business needs and scale as you grow.
            </p>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '20px' }} className="grid-2">
            {models.map((m, i) => (
              <div key={i} className="glass-card" style={{ padding: '28px 20px', background: '#fff', textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '14px' }}>
                <div style={{
                  width: '44px', height: '44px', borderRadius: '10px',
                  background: 'rgba(26,86,219,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center'
                }}>
                  {m.icon}
                </div>
                <h3 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--navy)', margin: 0 }}>{m.title}</h3>
                <p style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>{m.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Call to Action */}
      <section className="container" style={{ padding: '80px 24px 0' }}>
        <div className="glass-card" style={{ padding: '48px 36px', textAlign: 'center', background: 'linear-gradient(135deg, rgba(26,86,219,0.04) 0%, #fff 50%, rgba(26,86,219,0.04) 100%)', borderColor: 'rgba(26,86,219,0.15)' }}>
          <h2 style={{ fontSize: '1.8rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>
            Ready to Accelerate Your Digital Growth?
          </h2>
          <p style={{ color: 'var(--text-secondary)', margin: '0 0 24px', fontSize: '0.95rem' }}>
            Discuss your software architecture, cloud, or ERP project requirements with our experts.
          </p>
          <div style={{ display: 'flex', justifyContent: 'center', gap: '14px' }}>
            <NavLink to="/contact" className="btn-primary">
              Get in Touch <ArrowRight className="w-4 h-4" />
            </NavLink>
            <NavLink to="/solutions" className="btn-secondary">
              View Flagship Solutions
            </NavLink>
          </div>
        </div>
      </section>

    </div>
  );
}
