import { useState, useEffect } from 'react';
import { Mail, Phone, Globe, MapPin, Send, CheckCircle2, Sparkles, Smartphone, ShieldCheck } from 'lucide-react';

const heroBackgrounds = [
  '/bg_colosseum_rome.png',
  '/bg_eiffel_tower.png',
  '/bg_sigiriya.png',
  '/bg_pyramids_giza.png',
  '/bg_taj_mahal.png',
  '/bg_machu_picchu.png',
  '/bg_great_wall.png',
  '/bg_sydney_opera.png',
  '/bg_statue_liberty.png',
];

export default function Contact() {
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);
  const [submitted, setSubmitted] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const emptyForm = {
    name: '',
    email: '',
    company: '',
    topic: 'App Inquiry & Feedback',
    message: '',
    website: ''
  };
  const [formData, setFormData] = useState(emptyForm);

  // Sent to support@nexaround.com by the API. "Sent" only shows when the mail
  // really left; a failure keeps the message on screen with the support email.
  const handleSubmit = async (e) => {
    e.preventDefault();
    setSending(true);
    setError('');
    try {
      const res = await fetch('https://api.nexaround.com/api/v1/landing/contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          site: 'app.nexaround.com',
          name: formData.name.trim(),
          email: formData.email.trim(),
          company: formData.company.trim() || null,
          topic: formData.topic,
          message: formData.message.trim(),
          website: formData.website || null
        })
      });
      if (res.ok) {
        setSubmitted(true);
        setFormData(emptyForm);
      } else if (res.status === 429) {
        setError('Too many messages from here. Please email support@nexaround.com.');
      } else {
        setError('Your message could not be sent. Please check your details, or email support@nexaround.com.');
      }
    } catch {
      setError('Your message could not be sent. Please email support@nexaround.com.');
    } finally {
      setSending(false);
    }
  };

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '100px' }}>
      
      {/* ═══════════════════════════════════════════════════════ */}
      {/* ═══ HERO SECTION (EXACT MATCHING HOME PAGE LAYOUT & SIZE - 100VH) ═══ */}
      <section className="hero-section" style={{ 
        position: 'relative', 
        background: '#080a14', 
        overflow: 'hidden'
      }}>
        
        {/* Smooth Auto-Rotating Background Images with Cross-Fade */}
        {heroBackgrounds.map((bg, idx) => (
          <div
            key={bg}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              backgroundImage: `url(${bg})`,
              backgroundSize: 'cover',
              backgroundPosition: 'center 40%',
              opacity: idx === currentBgIndex ? 0.48 : 0,
              filter: 'brightness(1.1) contrast(1.05)',
              transform: idx === currentBgIndex ? 'scale(1.03)' : 'scale(1)',
              transition: 'opacity 1.4s ease-in-out, transform 5s ease-out',
              zIndex: 1,
              pointerEvents: 'none'
            }}
          />
        ))}

        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(90deg, rgba(8, 10, 20, 0.88) 0%, rgba(8, 10, 20, 0.55) 45%, rgba(8, 10, 20, 0.15) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        <div style={{
          position: 'absolute',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'linear-gradient(180deg, transparent 40%, rgba(8, 10, 20, 0.4) 75%, rgba(8, 10, 20, 0.98) 100%)',
          zIndex: 2,
          pointerEvents: 'none'
        }} />

        {/* Hero Content (Left-Aligned, Clean Typography Matching Home) */}
        <div className="container" style={{ position: 'relative', zIndex: 3 }}>
          <div style={{ maxWidth: '820px', textAlign: 'left' }}>
            
            {/* Main Headline */}
            <h1 style={{ 
              fontSize: 'clamp(2.8rem, 6vw, 4.6rem)', 
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
              fontSize: 'clamp(1.05rem, 1.8vw, 1.22rem)', 
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
              <span style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--brand-teal)', textTransform: 'uppercase', letterSpacing: '1px', display: 'block', marginBottom: '8px' }}>
                Support & Inquiries
              </span>
              <h3 style={{ fontSize: '1.35rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 20px' }}>
                NexAround Headquarters
              </h3>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '20px', fontSize: '0.95rem', color: 'var(--text-secondary)' }}>
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, marginTop: '2px' }}>
                    <MapPin style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--dark-charcoal)' }}>Colombo Office</div>
                    <address style={{ fontStyle: 'normal', color: 'var(--text-secondary)', lineHeight: 1.5, marginTop: '2px' }}>
                      No.47/3/1/1, 4th Lane, Madiwela,<br />
                      Kotte, Colombo, Sri Lanka
                    </address>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Mail style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--dark-charcoal)' }}>Email Support</div>
                    <a href="mailto:support@nexaround.com" style={{ color: 'var(--brand-teal)', fontWeight: 500 }}>support@nexaround.com</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Phone style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--dark-charcoal)' }}>Phone / WhatsApp</div>
                    <a href="tel:+97455816148" style={{ color: 'var(--brand-teal)', fontWeight: 500 }}>+974 5581 6148</a>
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
                  <div style={{ width: '44px', height: '44px', borderRadius: '12px', background: 'rgba(0, 122, 124, 0.1)', color: 'var(--brand-teal)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                    <Globe style={{ width: '20px', height: '20px' }} />
                  </div>
                  <div>
                    <div style={{ fontSize: '0.75rem', fontWeight: 500, color: 'var(--dark-charcoal)' }}>Official Domain</div>
                    <a href="https://nexaround.com" target="_blank" rel="noreferrer" style={{ color: 'var(--brand-teal)', fontWeight: 500 }}>nexaround.com</a>
                  </div>
                </div>
              </div>
            </div>

            <div className="feature-card" style={{ padding: '32px', background: 'var(--bg-light)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
                <ShieldCheck style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
                <h4 style={{ fontSize: '1.05rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: 0 }}>Fast Response Time</h4>
              </div>
              <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', margin: 0, lineHeight: 1.6 }}>
                Our engineering and product support team typically replies within 1 business day.
              </p>
            </div>

          </div>

          {/* Right: Contact Form */}
          <div className="feature-card" style={{ padding: '44px 38px', textAlign: 'left' }}>
            <h3 style={{ fontSize: '1.4rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 8px' }}>
              Send Us a Message
            </h3>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.94rem', margin: '0 0 28px' }}>
              Fill in the form below and we will route your inquiry to the appropriate department.
            </p>

            {submitted ? (
              <div style={{ background: 'var(--brand-teal-soft)', border: '1px solid rgba(0, 122, 124, 0.3)', borderRadius: '16px', padding: '36px', textAlign: 'center' }}>
                <CheckCircle2 style={{ width: '48px', height: '48px', color: 'var(--brand-teal)', margin: '0 auto 16px' }} />
                <h4 style={{ fontSize: '1.3rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 8px' }}>Message Sent!</h4>
                <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', margin: '0 0 20px' }}>
                  Thank you. Your message has been sent, and we will reply by email.
                </p>
                <button onClick={() => setSubmitted(false)} className="btn-teal">
                  Send Another Message
                </button>
              </div>
            ) : (
              <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Your Name *</label>
                  <input
                    type="text"
                    required
                    minLength={2}
                    placeholder="e.g. Sarah Connor"
                    className="form-input"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  />
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Email Address *</label>
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
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Inquiry Topic</label>
                  <select
                    className="form-select"
                    value={formData.topic}
                    onChange={(e) => setFormData({ ...formData, topic: e.target.value })}
                  >
                    <option>App Inquiry & Feedback</option>
                    <option>Destination / Tourism Board Partnership</option>
                    <option>Museum, Hotel or Experience Provider Partnership</option>
                    <option>Enterprise Software & Integration</option>
                    <option>Technical Consultation</option>
                    <option>Other</option>
                  </select>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.82rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '6px' }}>Message *</label>
                  <textarea
                    required
                    minLength={5}
                    rows="5"
                    placeholder="Tell us about your questions or requirements..."
                    className="form-textarea"
                    value={formData.message}
                    onChange={(e) => setFormData({ ...formData, message: e.target.value })}
                  />
                </div>

                <div style={{ position: 'absolute', left: '-9999px' }} aria-hidden="true">
                  <label>
                    Leave this empty
                    <input
                      type="text"
                      tabIndex={-1}
                      autoComplete="off"
                      value={formData.website}
                      onChange={(e) => setFormData({ ...formData, website: e.target.value })}
                    />
                  </label>
                </div>

                {error && (
                  <p role="alert" style={{ color: '#C0392B', fontSize: '0.9rem', margin: 0 }}>{error}</p>
                )}

                <button type="submit" disabled={sending} className="btn-teal" style={{ width: '100%', justifyContent: 'center', marginTop: '10px', opacity: sending ? 0.7 : 1 }}>
                  <Send style={{ width: '16px', height: '16px' }} />
                  <span>{sending ? 'Sending…' : 'Submit Message'}</span>
                </button>
              </form>
            )}
          </div>

        </div>
      </section>

    </div>
  );
}
