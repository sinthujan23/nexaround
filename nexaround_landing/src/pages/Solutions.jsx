import { 
  Monitor, BrainCircuit, Blocks, Cloud, Smartphone, 
  Check, ArrowRight, Sparkles 
} from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function Solutions() {
  const erpSubFeatures = [
    { name: 'Accounting', desc: 'Invoices, payments & live financial reporting.' },
    { name: 'Inventory', desc: 'Stock & warehouses in real time.' },
    { name: 'Manufacturing', desc: 'BOMs, work orders & supply chain planning.' },
    { name: 'HR & Payroll', desc: 'People tracking, attendance & payroll processing.' },
    { name: 'CRM & Sales', desc: 'Leads, pipelines & customer relationships.' },
    { name: 'Reports & BI', desc: 'Real-time corporate insights & customized dashboards.' }
  ];

  return (
    <div style={{ paddingBottom: '80px' }}>
      
      {/* Header */}
      <section style={{ paddingTop: '64px', textAlign: 'center', maxWidth: '700px', margin: '0 auto', padding: '64px 24px 0' }}>
        <div className="badge badge-orange" style={{ margin: '0 auto 20px' }}>Flagship Offerings</div>
        <h1 style={{ fontSize: 'clamp(2rem, 4.5vw, 2.8rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15 }}>
          Solutions that Drive <br />
          <span className="text-gradient-blue">Real Impact</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', lineHeight: 1.7, margin: 0 }}>
          We build future-ready solutions that solve complex problems and create measurable value.
        </p>
      </section>

      {/* Flagship 1: ERPNext */}
      <section className="container" style={{ paddingTop: '80px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div className="glass-card" style={{ padding: '48px 40px', borderLeft: '4px solid var(--blue)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '28px', textAlign: 'left' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '10px', background: 'rgba(26,86,219,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Monitor className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />
              </div>
              <div>
                <span style={{ fontSize: '0.72rem', fontFamily: 'var(--font-mono)', textTransform: 'uppercase', color: 'var(--blue)', fontWeight: 700, letterSpacing: '1px' }}>Flagship Offering</span>
                <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Complete ERPNext, delivered end-to-end</h2>
              </div>
            </div>
            
            <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0, maxWidth: '800px' }}>
              Run your entire business on one open-source platform — accounting, inventory, manufacturing, sales, HR, and more. We handle implementation, customization, migration, training, and support.
            </p>

            <ul style={{ display: 'flex', flexDirection: 'column', gap: '10px', listStyle: 'none', padding: 0, margin: 0 }}>
              <li style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.85rem', color: 'var(--text-primary)' }}>
                <Check className="w-4 h-4" style={{ color: 'var(--orange)' }} /> All-in-one — no per-user license lock-in
              </li>
              <li style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.85rem', color: 'var(--text-primary)' }}>
                <Check className="w-4 h-4" style={{ color: 'var(--orange)' }} /> Customized to your exact workflow
              </li>
              <li style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.85rem', color: 'var(--text-primary)' }}>
                <Check className="w-4 h-4" style={{ color: 'var(--orange)' }} /> Data migration, integrations & training included
              </li>
            </ul>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginTop: '12px' }} className="grid-2">
              {erpSubFeatures.map((f, i) => (
                <div key={i} style={{ padding: '18px', background: 'var(--bg-light)', borderRadius: '12px', border: '1px solid var(--border-color)' }}>
                  <div style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)' }}>{f.name}</div>
                  <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', marginTop: '4px' }}>{f.desc}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Flagship 2: AI, ML & Data */}
      <section className="container" style={{ paddingTop: '40px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div className="glass-card" style={{ padding: '48px 40px', borderLeft: '4px solid var(--orange)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '28px', textAlign: 'left' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '10px', background: 'rgba(232, 119, 34, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <BrainCircuit className="w-6 h-6 text-brand-orange" style={{ color: 'var(--orange)' }} />
              </div>
              <div>
                <span style={{ fontSize: '0.72rem', fontFamily: 'var(--font-mono)', textTransform: 'uppercase', color: 'var(--orange)', fontWeight: 700, letterSpacing: '1px' }}>AI, ML & DATA</span>
                <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Intelligent systems. Actionable insights.</h2>
              </div>
            </div>

            <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0, maxWidth: '800px' }}>
              We design artificial intelligence, machine learning, and data engineering solutions to automate processes, unlock hidden insights, and drive smarter business decisions.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '16px' }} className="grid-2">
              {[
                { title: 'Predictive Analytics', desc: 'Models for inventory, customer churn, and demand forecasting.' },
                { title: 'Live Data Pipelines', desc: 'Automated ETL and real-time streaming to unify SQL, ERPs, and APIs.' },
                { title: 'AI Process Automation', desc: 'Intelligent document parsing, LLMs, and automated workflows.' },
                { title: 'Executive BI Dashboards', desc: 'Real-time operational metrics and decision-ready dashboards.' }
              ].map((item, i) => (
                <div key={i} style={{ padding: '20px 16px', background: 'var(--bg-light)', borderRadius: '12px', border: '1px solid var(--border-color)' }}>
                  <div style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)' }}>{item.title}</div>
                  <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', marginTop: '6px', margin: 0 }}>{item.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Flagship 3: Blockchain & Web3 */}
      <section className="container" style={{ paddingTop: '40px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div className="glass-card" style={{ padding: '48px 40px', borderLeft: '4px solid var(--blue)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '28px', textAlign: 'left' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '10px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Blocks className="w-6 h-6 text-brand-blue" style={{ color: 'var(--blue)' }} />
              </div>
              <div>
                <span style={{ fontSize: '0.72rem', fontFamily: 'var(--font-mono)', textTransform: 'uppercase', color: 'var(--blue)', fontWeight: 700, letterSpacing: '1px' }}>BLOCKCHAIN & WEB3</span>
                <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Decentralized systems built for trust and transparency</h2>
              </div>
            </div>

            <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0, maxWidth: '800px' }}>
              We design and build blockchain-powered solutions — from smart contracts to decentralized applications — that bring transparency, security, and automation to critical business processes.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '16px' }} className="grid-2">
              {[
                { title: 'Smart Contracts', desc: 'Secure, audited contract logic for automated, trustless transactions.' },
                { title: 'dApp Development', desc: 'End-to-end decentralized applications across leading chains.' },
                { title: 'Chain Integration', desc: 'Connecting blockchain layers with existing ERP, CRM, and business systems.' },
                { title: 'Digital Asset Tokenization', desc: 'Tokenizing assets and building the infrastructure to manage them.' }
              ].map((item, i) => (
                <div key={i} style={{ padding: '20px 16px', background: 'var(--bg-light)', borderRadius: '12px', border: '1px solid var(--border-color)' }}>
                  <div style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)' }}>{item.title}</div>
                  <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', marginTop: '6px', margin: 0 }}>{item.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* Flagship 4: Cloud & DevOps */}
      <section className="container" style={{ paddingTop: '40px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div className="glass-card" style={{ padding: '48px 40px', borderLeft: '4px solid var(--orange)' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '28px', textAlign: 'left' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '10px', background: 'rgba(232, 119, 34, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Cloud className="w-6 h-6 text-brand-orange" style={{ color: 'var(--orange)' }} />
              </div>
              <div>
                <span style={{ fontSize: '0.72rem', fontFamily: 'var(--font-mono)', textTransform: 'uppercase', color: 'var(--orange)', fontWeight: 700, letterSpacing: '1px' }}>CLOUD & DEVOPS</span>
                <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>High-Performance Cloud Infrastructure</h2>
              </div>
            </div>

            <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0, maxWidth: '800px' }}>
              We construct secure, scalable cloud infrastructure and automate release pipelines (CI/CD) to ensure minimal downtime and rapid time-to-value for enterprise applications.
            </p>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px' }} className="grid-2">
              {[
                { title: 'Infrastructure as Code', desc: 'Automated environment provisioning via Terraform for AWS, Azure, and Google Cloud.' },
                { title: 'CI/CD Pipelines', desc: 'Secure, automated testing and build cycles to deliver software releases with speed.' },
                { title: 'Containerization & Scaling', desc: 'Orchestrating applications with Docker and Kubernetes for zero-downtime scaling.' }
              ].map((item, i) => (
                <div key={i} style={{ padding: '20px 16px', background: 'var(--bg-light)', borderRadius: '12px', border: '1px solid var(--border-color)' }}>
                  <div style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)' }}>{item.title}</div>
                  <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', marginTop: '6px', margin: 0 }}>{item.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* nexARound App Showcase Product */}
      <section className="container" style={{ paddingTop: '80px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div className="glass-card" style={{ padding: '48px 40px', background: 'linear-gradient(135deg, rgba(26,86,219,0.02) 0%, rgba(255,255,255,1) 50%, rgba(26,86,219,0.02) 100%)' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: '40px', alignItems: 'center', textAlign: 'left' }}>
            <div>
              <img 
                src="/app_icon.png" 
                alt="nexARound Icon" 
                style={{ width: '48px', height: '48px', borderRadius: '10px', marginBottom: '16px', objectFit: 'cover' }} 
              />
              <span className="badge badge-blue" style={{ marginBottom: '12px' }}>In-House Software Product</span>
              <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px' }}>
                nexARound Travel Companion
              </h2>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 20px' }}>
                Built in-house, nexARound is an AI-powered spatial tourism companion. It integrates multi-day itinerary generation (Odyssey), curated guides for 63 world-class museums, live AR landmark scanning, location-aware attraction discovery, and community-driven travel stories.
              </p>
              <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
                <span className="badge" style={{ fontSize: '10px' }}>AI Itinerary Planner</span>
                <span className="badge" style={{ fontSize: '10px' }}>AR Camera overlays</span>
                <span className="badge" style={{ fontSize: '10px' }}>Museum Routes</span>
              </div>
            </div>

            <div style={{ background: 'var(--bg-light)', border: '1px solid var(--border-color)', borderRadius: '16px', padding: '32px', display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div style={{ fontSize: '0.72rem', fontFamily: 'var(--font-mono)', fontWeight: 700, color: 'var(--blue)' }}>PRODUCT CAPABILITIES</div>
              {[
                { name: 'Odyssey AI Trip Planner', desc: 'Generates day-by-day travel plans based on mood and budget.' },
                { name: 'Museum guide engine', desc: 'Custom time-based visit paths for 63 major art galleries.' },
                { name: 'Around You discovery', desc: 'Google Places integration with maps, budget tracking & filters.' }
              ].map((p, i) => (
                <div key={i} style={{ display: 'flex', gap: '12px', alignItems: 'flex-start' }}>
                  <Smartphone className="w-5 h-5" style={{ color: 'var(--blue)', marginTop: '2px', flexShrink: 0 }} />
                  <div>
                    <div style={{ fontWeight: 700, fontSize: '0.88rem', color: 'var(--navy)' }}>{p.name}</div>
                    <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', marginTop: '2px' }}>{p.desc}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

    </div>
  );
}
