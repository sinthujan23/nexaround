import { 
  Monitor, BrainCircuit, Blocks, Cloud, 
  ArrowRight, Sparkles
} from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function Solutions() {
  const erpModules = [
    { name: 'Financial Accounting', desc: 'Real-time ledger, automated invoicing, multi-currency & tax reporting.' },
    { name: 'Inventory & Supply Chain', desc: 'Live stock tracking, multi-warehouse management & serial/batch tracking.' },
    { name: 'Manufacturing & BOMs', desc: 'Work orders, Bill of Materials (BOM), production scheduling & MRP.' },
    { name: 'HR & Payroll Engine', desc: 'Employee lifecycle, attendance tracking, leave management & automated payroll.' },
    { name: 'CRM & Sales Pipeline', desc: 'Lead tracking, deal pipelines, customer portals & quotation management.' },
    { name: 'Executive BI Reports', desc: 'Custom executive dashboards, real-time analytics & automated reporting.' }
  ];

  const aiSolutions = [
    { title: 'Predictive Analytics', desc: 'Custom ML models for demand forecasting, churn prediction & risk analysis.' },
    { title: 'AI Document Processing', desc: 'Automated invoice parsing, contract analysis & LLM-driven document extraction.' },
    { title: 'Live Data Pipelines', desc: 'Real-time ETL streaming unifying relational databases, ERPs, and external APIs.' },
    { title: 'Executive BI Dashboards', desc: 'Decision-ready business intelligence dashboards built for C-suite leaders.' }
  ];

  const web3Solutions = [
    { title: 'Smart Contract Security', desc: 'Audited, secure smart contract architecture across Ethereum, Polygon & Solana.' },
    { title: 'dApp Engineering', desc: 'High-performance decentralized web and mobile applications with Web3 wallet support.' },
    { title: 'Asset Tokenization', desc: 'Tokenomics design, RWA tokenization platforms, and digital asset management.' },
    { title: 'Enterprise Web3 Gateways', desc: 'Connecting blockchain ledgers seamlessly with traditional ERP & CRM systems.' }
  ];

  const cloudSolutions = [
    { title: 'Infrastructure as Code', desc: 'Automated cloud environment provisioning using Terraform for AWS & Azure.' },
    { title: 'CI/CD Automation', desc: 'Zero-downtime automated build, security scan, and deployment pipelines.' },
    { title: 'Kubernetes Orchestration', desc: 'Containerized microservices scaling with automated load balancing & failover.' },
    { title: 'Cloud Security & Compliance', desc: 'Hardened network architecture, encryption at rest/transit & automated compliance.' }
  ];

  return (
    <div style={{ paddingBottom: '100px' }}>
      
      {/* Header Section */}
      <section style={{ textAlign: 'center', maxWidth: '900px', margin: '0 auto', padding: '160px 24px 64px', position: 'relative' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 22px' }}>
          <Sparkles style={{ width: '14px', height: '14px' }} /> Enterprise Solutions
        </div>
        <h1 style={{ fontSize: 'clamp(2.5rem, 5vw, 3.6rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 20px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
          Turnkey Solutions Engineered for <br />
          <span className="text-gradient-blue">Measurable Business Growth</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.12rem', lineHeight: 1.7, margin: 0, maxWidth: '720px', marginLeft: 'auto', marginRight: 'auto' }}>
          We design and deploy robust, enterprise-grade software architectures tailored to solve complex operational challenges.
        </p>
      </section>

      {/* SOLUTION 1: ERPNext Business Systems (Alternating Split: Image Left / Content Right) */}
      <section className="container" style={{ padding: '36px 40px 0' }}>
        <div className="service-page-card" style={{ padding: '52px 48px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: '48px', alignItems: 'center' }} className="grid-2">
            
            <img 
              src="/solution_erpnext.png" 
              alt="ERPNext Dashboard Platform Visual" 
              style={{ width: '100%', height: '340px', objectFit: 'cover', borderRadius: 'var(--radius-md)', border: '1px solid rgba(26, 86, 219, 0.2)', boxShadow: 'var(--shadow-md)' }}
            />

            <div style={{ textAlign: 'left' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Monitor style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', letterSpacing: '1px' }}>Enterprise Suite</div>
                    <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Complete ERPNext Systems</h2>
                  </div>
                </div>
                <span style={{ fontSize: '2.4rem', fontWeight: 800, color: 'rgba(26, 86, 219, 0.15)', fontFamily: 'var(--font-mono)' }}>01</span>
              </div>

              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 28px' }}>
                Unify your operational workflow on a single powerful ERP platform. We handle end-to-end implementation, custom module development, data migration, third-party API integration, and ongoing corporate support.
              </p>

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '14px' }}>
                {erpModules.slice(0, 4).map((m, i) => (
                  <div key={i} style={{ padding: '16px 16px', background: 'rgba(26, 86, 219, 0.03)', border: '1px solid rgba(26, 86, 219, 0.08)', borderRadius: '12px' }}>
                    <div style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '4px' }}>{m.name}</div>
                    <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.45 }}>{m.desc}</div>
                  </div>
                ))}
              </div>
            </div>

          </div>
        </div>
      </section>

      {/* SOLUTION 2: AI, ML & Data (Alternating Split: Content Left / Image Right) */}
      <section className="container" style={{ padding: '36px 40px 0' }}>
        <div className="service-page-card" style={{ padding: '52px 48px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '48px', alignItems: 'center' }} className="grid-2">
            
            <div style={{ textAlign: 'left' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(232, 119, 34, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <BrainCircuit style={{ width: '24px', height: '24px', color: 'var(--orange)' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', letterSpacing: '1px' }}>Intelligence Engine</div>
                    <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>AI, ML & Predictive Systems</h2>
                  </div>
                </div>
                <span style={{ fontSize: '2.4rem', fontWeight: 800, color: 'rgba(232, 119, 34, 0.15)', fontFamily: 'var(--font-mono)' }}>02</span>
              </div>

              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 28px' }}>
                Turn your raw business data into actionable automated intelligence. We design custom machine learning models, LLM document parsers, and real-time ETL pipelines.
              </p>

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '14px' }}>
                {aiSolutions.map((ai, i) => (
                  <div key={i} style={{ padding: '18px 16px', background: 'rgba(232, 119, 34, 0.03)', border: '1px solid rgba(232, 119, 34, 0.1)', borderRadius: '12px' }}>
                    <div style={{ fontSize: '0.9rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '4px' }}>{ai.title}</div>
                    <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.45 }}>{ai.desc}</div>
                  </div>
                ))}
              </div>
            </div>

            <img 
              src="/solution_ai.png" 
              alt="AI Data Engine Platform Visual" 
              style={{ width: '100%', height: '340px', objectFit: 'cover', borderRadius: 'var(--radius-md)', border: '1px solid rgba(232, 119, 34, 0.25)', boxShadow: 'var(--shadow-md)' }}
            />

          </div>
        </div>
      </section>

      {/* SOLUTION 3: Blockchain & Web3 (Alternating Split: Image Left / Content Right) */}
      <section className="container" style={{ padding: '36px 40px 0' }}>
        <div className="service-page-card" style={{ padding: '52px 48px' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.2fr', gap: '48px', alignItems: 'center' }} className="grid-2">
            
            <img 
              src="/solution_web3.png" 
              alt="Web3 Infrastructure Visual" 
              style={{ width: '100%', height: '320px', objectFit: 'cover', borderRadius: 'var(--radius-md)', border: '1px solid rgba(26, 86, 219, 0.2)', boxShadow: 'var(--shadow-md)' }}
            />

            <div style={{ textAlign: 'left' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(26, 86, 219, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Blocks style={{ width: '24px', height: '24px', color: 'var(--blue)' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--blue)', textTransform: 'uppercase', letterSpacing: '1px' }}>Decentralized Trust</div>
                    <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Blockchain & Web3 Platforms</h2>
                  </div>
                </div>
                <span style={{ fontSize: '2.4rem', fontWeight: 800, color: 'rgba(26, 86, 219, 0.15)', fontFamily: 'var(--font-mono)' }}>03</span>
              </div>

              <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 28px' }}>
                Secure, audited smart contracts, asset tokenization engines, and decentralized dApps built for enterprise trust and transparency.
              </p>

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '14px' }}>
                {web3Solutions.map((w, i) => (
                  <div key={i} style={{ padding: '18px 16px', background: 'rgba(26, 86, 219, 0.03)', border: '1px solid rgba(26, 86, 219, 0.08)', borderRadius: '12px' }}>
                    <div style={{ fontSize: '0.88rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '4px' }}>{w.title}</div>
                    <div style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.45 }}>{w.desc}</div>
                  </div>
                ))}
              </div>
            </div>

          </div>
        </div>
      </section>

      {/* SOLUTION 4: Cloud & DevOps */}
      <section className="container" style={{ padding: '36px 40px 0' }}>
        <div className="service-page-card" style={{ padding: '52px 48px', textAlign: 'left' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '14px', background: 'rgba(15, 23, 42, 0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Cloud style={{ width: '24px', height: '24px', color: 'var(--navy)' }} />
              </div>
              <div>
                <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--navy)', textTransform: 'uppercase', letterSpacing: '1px' }}>Cloud DevOps</div>
                <h2 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', margin: 0 }}>Cloud Infrastructure & DevOps</h2>
              </div>
            </div>
            <span style={{ fontSize: '2.4rem', fontWeight: 800, color: 'rgba(15, 23, 42, 0.15)', fontFamily: 'var(--font-mono)' }}>04</span>
          </div>

          <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: '0 0 32px', maxWidth: '820px' }}>
            Scalable, resilient cloud infrastructure. We implement Infrastructure as Code (IaC), zero-downtime CI/CD pipelines, Kubernetes container orchestration, and multi-region cloud security.
          </p>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '18px' }} className="grid-2">
            {cloudSolutions.map((c, i) => (
              <div key={i} style={{ padding: '22px 18px', background: 'rgba(15, 23, 42, 0.03)', border: '1px solid rgba(15, 23, 42, 0.08)', borderRadius: '14px' }}>
                <div style={{ fontSize: '0.92rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>{c.title}</div>
                <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>{c.desc}</div>
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
            Need a Custom Solution for Your Enterprise?
          </h2>
          <p style={{ color: 'var(--text-secondary)', margin: '0 0 36px', fontSize: '1.05rem', maxWidth: '600px', marginLeft: 'auto', marginRight: 'auto', lineHeight: 1.7 }}>
            Schedule an architectural consultation with our senior engineering leads to map out your software roadmap.
          </p>
          <NavLink to="/contact" className="btn-primary">
            Book Architectural Consultation <ArrowRight style={{ width: '18px', height: '18px' }} />
          </NavLink>
        </div>
      </section>

    </div>
  );
}
