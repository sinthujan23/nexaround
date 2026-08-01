import { useState } from 'react';
import { Mail, Phone, Globe, MapPin, Send, CheckCircle2, Sparkles } from 'lucide-react';

export default function Contact() {
  const [submitted, setSubmitted] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    company: '',
    service: 'Enterprise Software & Development',
    message: ''
  });

  const handleSubmit = (e) => {
    e.preventDefault();
    setSubmitted(true);
  };

  return (
    <div style={{ paddingBottom: '100px' }}>
      
      {/* Header Section */}
      <section style={{ textAlign: 'center', maxWidth: '900px', margin: '0 auto', padding: '160px 24px 64px' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 22px' }}>
          <Sparkles style={{ width: '14px', height: '14px' }} /> Direct Engineering Line
        </div>
        <h1 style={{ fontSize: 'clamp(2.5rem, 5vw, 3.6rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 20px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
          Let’s Build Something <br />
          <span className="text-gradient-blue">Extraordinary Together</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.12rem', lineHeight: 1.7, margin: 0, maxWidth: '680px', marginLeft: 'auto', marginRight: 'auto' }}>
          Whether you need full-stack software development, custom ERPNext integration, AI data pipelines, or a flagship mobile app build, our senior team is ready.
        </p>
      </section>

      {/* Main Contact Grid */}
      <section className="container" style={{ padding: '0 40px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.3fr', gap: '48px', alignItems: 'start' }} className="grid-2">
          
          {/* Left: Contact Info */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '24px' }}>
            <div className="service-page-card" style={{ padding: '36px 32px' }}>
              <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--orange)', textTransform: 'uppercase', letterSpacing: '1px', marginBottom: '8px' }}>Global Headquarters</div>
              <h3 style={{ fontSize: '1.3rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px' }}>Technical Operations & Support</h3>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '20px', fontSize: '0.95rem', color: 'var(--text-secondary)' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '42px', height: '42px', borderRadius: '12px', background: 'rgba(26,86,219,0.08)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Mail style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--navy)' }}>Email Inquiry</div>
                    <a href="mailto:support@nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>support@nexaround.com</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '42px', height: '42px', borderRadius: '12px', background: 'rgba(26,86,219,0.08)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Phone style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--navy)' }}>Direct Phone</div>
                    <a href="tel:+97455816148" style={{ color: 'var(--navy)', fontWeight: 600 }}>+974 5581 6148</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '42px', height: '42px', borderRadius: '12px', background: 'rgba(26,86,219,0.08)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Globe style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--navy)' }}>Website</div>
                    <a href="https://www.nexaround.com" target="_blank" rel="noreferrer" style={{ color: 'var(--navy)', fontWeight: 600 }}>www.nexaround.com</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '42px', height: '42px', borderRadius: '12px', background: 'rgba(26,86,219,0.08)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <MapPin style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--navy)' }}>Coverage Region</div>
                    <span style={{ color: 'var(--navy)', fontWeight: 600 }}>Sri Lanka & Global Engineering Clients</span>
                  </div>
                </div>
              </div>
            </div>

            <div style={{ padding: '28px 30px', background: 'rgba(26,86,219,0.03)', border: '1px solid rgba(26,86,219,0.12)', borderRadius: 'var(--radius-md)' }}>
              <div style={{ fontSize: '0.92rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '6px' }}>Fast Technical Response</div>
              <p style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                Our senior engineering team reviews all incoming inquiries within 24 business hours to provide an initial architectural assessment.
              </p>
            </div>
          </div>

          {/* Right: Glass Form */}
          <div className="service-page-card" style={{ padding: '44px 40px', textAlign: 'left' }}>
            {submitted ? (
              <div style={{ textAlign: 'center', padding: '40px 20px' }}>
                <div style={{ width: '64px', height: '64px', borderRadius: '50%', background: 'rgba(26, 86, 219, 0.1)', color: 'var(--blue)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 20px' }}>
                  <CheckCircle2 style={{ width: '32px', height: '32px' }} />
                </div>
                <h3 style={{ fontSize: '1.6rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 12px' }}>Inquiry Received</h3>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.98rem', lineHeight: 1.65, margin: '0 0 28px' }}>
                  Thank you for reaching out. A senior engineering lead will contact you shortly to discuss your project requirements.
                </p>
                <button onClick={() => setSubmitted(false)} className="btn-primary" style={{ padding: '12px 28px', fontSize: '0.9rem' }}>
                  Send Another Inquiry
                </button>
              </div>
            ) : (
              <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '22px' }}>
                <h3 style={{ fontSize: '1.45rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 4px' }}>Send Us a Message</h3>
                <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', margin: '0 0 8px' }}>Fill out the form below and we will get back to you promptly.</p>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '18px' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>Your Name *</label>
                    <input 
                      type="text" 
                      required 
                      className="form-input" 
                      placeholder="e.g. Alexander Wright" 
                      value={formData.name}
                      onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>Business Email *</label>
                    <input 
                      type="email" 
                      required 
                      className="form-input" 
                      placeholder="alex@company.com" 
                      value={formData.email}
                      onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '18px' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>Company Name</label>
                    <input 
                      type="text" 
                      className="form-input" 
                      placeholder="e.g. Global Tech Solutions" 
                      value={formData.company}
                      onChange={(e) => setFormData({ ...formData, company: e.target.value })}
                    />
                  </div>

                  <div>
                    <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>Primary Service Required</label>
                    <select 
                      className="form-select"
                      value={formData.service}
                      onChange={(e) => setFormData({ ...formData, service: e.target.value })}
                    >
                      <option value="Enterprise Software & Development">Enterprise Software & Development</option>
                      <option value="ERPNext Implementation">ERPNext Implementation</option>
                      <option value="AI & Data Intelligence">AI & Data Intelligence</option>
                      <option value="Blockchain & Web3">Blockchain & Web3</option>
                      <option value="Flagship Mobile App Customization">Flagship Mobile App Customization</option>
                    </select>
                  </div>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.8rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>Project Summary & Requirements *</label>
                  <textarea 
                    required 
                    rows={5} 
                    className="form-textarea" 
                    placeholder="Tell us about your objectives, timeline, and technical scope..."
                    value={formData.message}
                    onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                  />
                </div>

                <button type="submit" className="btn-primary" style={{ marginTop: '8px', justifyContent: 'center', width: '100%' }}>
                  Submit Technical Inquiry <Send style={{ width: '16px', height: '16px' }} />
                </button>
              </form>
            )}
          </div>

        </div>
      </section>

    </div>
  );
}
