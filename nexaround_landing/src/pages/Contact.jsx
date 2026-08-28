import { useState } from 'react';
import { Mail, Phone, Globe, MapPin, Send, CheckCircle2, Sparkles, Smartphone, ShieldCheck } from 'lucide-react';

export default function Contact() {
  const [submitted, setSubmitted] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    company: '',
    topic: 'App Inquiry & Feedback',
    message: ''
  });

  const handleSubmit = (e) => {
    e.preventDefault();
    setSubmitted(true);
  };

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '100px' }}>
      
      {/* ═══════════════════════════════════════════════════════ */}
      {/* ═══ HERO SECTION (MATCHING HOME PAGE LAYOUT) ═══ */}
      <section className="hero-section" style={{ 
        position: 'relative', 
        minHeight: '65vh', 
        display: 'flex', 
        alignItems: 'center', 
        background: '#080a14', 
        overflow: 'hidden',
        padding: '170px 0 80px'
      }}>
        
        {/* Background Visual with Directional Soft Left & Bottom Vignette */}
        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          right: 0,
          bottom: 0,
          backgroundImage: 'url(/bg_colosseum_rome.png)',
          backgroundSize: 'cover',
          backgroundPosition: 'center 40%',
          opacity: 0.45,
          filter: 'brightness(1.1) contrast(1.05)',
          zIndex: 1,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(90deg, rgba(8, 10, 20, 0.92) 0%, rgba(8, 10, 20, 0.65) 55%, rgba(8, 10, 20, 0.25) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(180deg, transparent 40%, rgba(8, 10, 20, 0.5) 75%, rgba(8, 10, 20, 0.98) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        {/* Hero Content (Left-Aligned, Clean Typography Matching Home) */}
        <div className="container" style={{ position: 'relative', zIndex: 3 }}>
          <div style={{ maxWidth: '820px', textAlign: 'left' }}>
            
            {/* Main Headline */}
            <h1 style={{ 
              fontSize: 'clamp(2.6rem, 5.5vw, 4.2rem)', 
              fontWeight: 300, 
              color: '#ffffff', 
              lineHeight: 1.15, 
              letterSpacing: '-0.03em', 
              margin: '0 0 20px',
              textShadow: '0 2px 14px rgba(0,0,0,0.5)'
            }}>
              Get in Touch with <span style={{ fontWeight: 500, color: '#00d2d3' }}>NexAround</span>.
            </h1>

            {/* Sub-Headline */}
            <p style={{ 
              fontSize: 'clamp(1.05rem, 1.8vw, 1.2rem)', 
              color: 'rgba(255, 255, 255, 0.88)', 
              lineHeight: 1.65, 
              margin: 0, 
              maxWidth: '660px',
              fontWeight: 300,
              textShadow: '0 2px 10px rgba(0,0,0,0.5)'
            }}>
              Whether you are a traveler with questions, a tourism board seeking destination integration, or an enterprise partner, our team is here to assist.
            </p>

          </div>
        </div>
      </section>

      {/* Main Grid */}
      <section className="container" style={{ padding: '80px 32px 0' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.3fr', gap: '48px', alignItems: 'start' }} className="grid-2">
          
          {/* Left: Contact Info */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '24px' }}>
            
            <div className="feature-card" style={{ padding: '36px 32px' }}>
              <span style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '8px' }}>
                Support & Inquiries
              </span>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 20px' }}>
                NexAround Headquarters
              </h3>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '20px', fontSize: '0.95rem', color: 'var(--text-secondary)' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Mail style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--dark-charcoal)' }}>Email Support</div>
                    <a href="mailto:support@nexaround.com" style={{ color: 'var(--brand-teal)', fontWeight: 600 }}>support@nexaround.com</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Phone style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--dark-charcoal)' }}>Phone / WhatsApp</div>
                    <a href="tel:+97455816148" style={{ color: 'var(--brand-teal)', fontWeight: 600 }}>+974 5581 6148</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Globe style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--dark-charcoal)' }}>Official Domain</div>
                    <a href="https://nexaround.com" target="_blank" rel="noreferrer" style={{ color: 'var(--brand-teal)', fontWeight: 600 }}>nexaround.com</a>
                  </div>
                </div>
              </div>
            </div>

            <div className="feature-card" style={{ padding: '32px', background: 'var(--bg-light)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                <ShieldCheck style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
                <h4 style={{ fontSize: '1.05rem', fontWeight: 800, color: 'var(--dark-charcoal)', margin: 0 }}>Fast Response Time</h4>
              </div>
              <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.6 }}>
                Our engineering and product support team typically replies within 1 business day.
              </p>
            </div>

          </div>

          {/* Right: Contact Form */}
          <div className="feature-card" style={{ padding: '44px 38px', textAlign: 'left' }}>
            <h3 style={{ fontSize: '1.4rem', fontWeight: 900, color: 'var(--dark-charcoal)', margin: '0 0 8px' }}>
              Send Us a Message
            </h3>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.94rem', margin: '0 0 28px' }}>
              Fill in the form below and we will route your inquiry to the appropriate department.
            </p>

            {submitted ? (
              <div style={{ background: 'var(--brand-teal-soft)', border: '1px solid rgba(0, 122, 124, 0.3)', borderRadius: '16px', padding: '36px', textAlign: 'center' }}>
                <CheckCircle2 style={{ width: '48px', height: '48px', color: 'var(--brand-teal)', margin: '0 auto 16px' }} />
                <h4 style={{ fontSize: '1.3rem', fontWeight: 800, color: 'var(--dark-charcoal)', margin: '0 0 8px' }}>Message Received!</h4>
                <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', margin: '0 0 20px' }}>
                  Thank you for reaching out. A NexAround team member will contact you shortly.
                </p>
                <button onClick={() => setSubmitted(false)} className="btn-teal">
                  Send Another Message
                </button>
              </div>
            ) : (
              <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Your Name *</label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. Sarah Connor"
                    className="form-input"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  />
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Email Address *</label>
                  <input
                    type="email"
                    required
                    placeholder="sarah@example.com"
                    className="form-input"
                    value={formData.email}
                    onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                  />
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Inquiry Topic</label>
                  <select
                    className="form-select"
                    value={formData.topic}
                    onChange={(e) => setFormData({ ...formData, topic: e.target.value })}
                  >
                    <option>App Inquiry & Feedback</option>
                    <option>Destination / Tourism Board Partnership</option>
                    <option>Enterprise Software & Integration</option>
                    <option>Technical Consultation</option>
                    <option>Other</option>
                  </select>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 700, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Message *</label>
                  <textarea
                    required
                    rows="5"
                    placeholder="Tell us about your questions or requirements..."
                    className="form-textarea"
                    value={formData.message}
                    onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                  />
                </div>

                <button type="submit" className="btn-teal" style={{ width: '100%', justifyContent: 'center', marginTop: '10px' }}>
                  <Send style={{ width: '16px', height: '16px' }} />
                  <span>Submit Message</span>
                </button>
              </form>
            )}
          </div>

        </div>
      </section>

    </div>
  );
}
