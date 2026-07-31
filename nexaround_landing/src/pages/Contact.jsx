import { useState } from 'react';
import { 
  Mail, Phone, Globe, Send, ShieldCheck, 
  Users, Eye, Target, Sparkles, CheckCircle2 
} from 'lucide-react';

export default function Contact() {
  const [submitted, setSubmitted] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    company: '',
    subject: 'General Inquiry',
    message: ''
  });

  const handleSubmit = (e) => {
    e.preventDefault();
    setSubmitted(true);
    setTimeout(() => {
      setSubmitted(false);
      setFormData({ name: '', email: '', company: '', subject: 'General Inquiry', message: '' });
    }, 3000);
  };

  const partnerReasons = [
    { title: 'Expert Team', desc: 'Skilled professionals with deep domain knowledge and hands-on experience.' },
    { title: 'Quality & Reliability', desc: 'We follow industry best practices to deliver secure, robust, and scalable solutions.' },
    { title: 'Agile & Transparent', desc: 'Agile delivery with clear communication and full transparency at every step.' },
    { title: 'Innovation Driven', desc: 'We leverage emerging technologies to build innovative solutions.' },
    { title: 'Long-term Partnership', desc: 'We focus on building long-term relationships and shared success.' }
  ];

  return (
    <div style={{ paddingBottom: '80px' }}>
      
      {/* Header */}
      <section style={{ paddingTop: '64px', textAlign: 'center', maxWidth: '700px', margin: '0 auto', padding: '64px 24px 0' }}>
        <div className="badge badge-orange" style={{ margin: '0 auto 20px' }}>Connect With Us</div>
        <h1 style={{ fontSize: 'clamp(2rem, 4.5vw, 2.8rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15 }}>
          Let's Build Something <br />
          <span className="text-gradient-blue">Extraordinary Together</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.05rem', lineHeight: 1.7, margin: 0 }}>
          We are ready to turn your ideas into powerful digital solutions. Get in touch with our team today.
        </p>
      </section>

      {/* Form and info row */}
      <section className="container" style={{ paddingTop: '64px', paddingLeft: '24px', paddingRight: '24px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1.2fr 1fr', gap: '32px' }} className="grid-2">
          
          {/* Form */}
          <div className="glass-card" style={{ padding: '40px 36px' }}>
            {submitted ? (
              <div style={{ textAlign: 'center', padding: '40px 0' }}>
                <CheckCircle2 className="w-12 h-12 text-brand-blue" style={{ color: 'var(--blue)', margin: '0 auto 16px' }} />
                <h3 style={{ fontSize: '1.2rem', fontWeight: 800, color: 'var(--navy)', margin: '0 0 8px' }}>Thank You!</h3>
                <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', margin: 0 }}>Your message has been sent. We'll get back to you shortly.</p>
              </div>
            ) : (
              <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '16px', textAlign: 'left' }}>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }} className="grid-2">
                  <div>
                    <label style={{ display: 'block', fontSize: '0.7rem', fontFamily: 'var(--font-mono)', color: '#8a8f9d', marginBottom: '6px', fontWeight: 600 }}>YOUR NAME</label>
                    <input 
                      type="text" 
                      required
                      placeholder="Alex Morgan" 
                      value={formData.name}
                      onChange={(e) => setFormData({...formData, name: e.target.value})}
                      style={{ width: '100%', padding: '10px 14px', background: '#f8f9fa', border: '1px solid var(--border-color)', borderRadius: '10px', fontSize: '0.82rem', color: '#121212', outline: 'none' }} 
                    />
                  </div>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.7rem', fontFamily: 'var(--font-mono)', color: '#8a8f9d', marginBottom: '6px', fontWeight: 600 }}>EMAIL ADDRESS</label>
                    <input 
                      type="email" 
                      required
                      placeholder="alex@company.com" 
                      value={formData.email}
                      onChange={(e) => setFormData({...formData, email: e.target.value})}
                      style={{ width: '100%', padding: '10px 14px', background: '#f8f9fa', border: '1px solid var(--border-color)', borderRadius: '10px', fontSize: '0.82rem', color: '#121212', outline: 'none' }} 
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px' }} className="grid-2">
                  <div>
                    <label style={{ display: 'block', fontSize: '0.7rem', fontFamily: 'var(--font-mono)', color: '#8a8f9d', marginBottom: '6px', fontWeight: 600 }}>COMPANY NAME</label>
                    <input 
                      type="text" 
                      placeholder="Acme Corp" 
                      value={formData.company}
                      onChange={(e) => setFormData({...formData, company: e.target.value})}
                      style={{ width: '100%', padding: '10px 14px', background: '#f8f9fa', border: '1px solid var(--border-color)', borderRadius: '10px', fontSize: '0.82rem', color: '#121212', outline: 'none' }} 
                    />
                  </div>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.7rem', fontFamily: 'var(--font-mono)', color: '#8a8f9d', marginBottom: '6px', fontWeight: 600 }}>SUBJECT</label>
                    <select 
                      value={formData.subject}
                      onChange={(e) => setFormData({...formData, subject: e.target.value})}
                      style={{ width: '100%', padding: '10px 14px', background: '#f8f9fa', border: '1px solid var(--border-color)', borderRadius: '10px', fontSize: '0.82rem', color: '#121212', outline: 'none', height: '38px' }}
                    >
                      <option>General Inquiry</option>
                      <option>ERPNext Implementation</option>
                      <option>Custom Software Project</option>
                      <option>AI / Data Solutions</option>
                      <option>Partnership Inquiry</option>
                    </select>
                  </div>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '0.7rem', fontFamily: 'var(--font-mono)', color: '#8a8f9d', marginBottom: '6px', fontWeight: 600 }}>MESSAGE</label>
                  <textarea 
                    rows="4" 
                    required
                    placeholder="How can we help your business succeed?" 
                    value={formData.message}
                    onChange={(e) => setFormData({...formData, message: e.target.value})}
                    style={{ width: '100%', padding: '10px 14px', background: '#f8f9fa', border: '1px solid var(--border-color)', borderRadius: '10px', fontSize: '0.82rem', color: '#121212', outline: 'none', resize: 'vertical' }} 
                  />
                </div>

                <button type="submit" className="btn-primary" style={{ width: '100%', justifyContent: 'center' }}>
                  <Send className="w-4 h-4" /> Send Message
                </button>
              </form>
            )}
          </div>

          {/* Info */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '28px', justifyContent: 'center' }}>
            <div>
              <h3 style={{ fontSize: '1.25rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '8px' }}>NexARound Technologies</h3>
              <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                Enterprise software firm specializing in custom development, AI data systems, ERP deployments, and digital transformation.
              </p>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ width: '38px', height: '38px', borderRadius: '50%', background: 'rgba(26,86,219,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Mail className="w-5 h-5 text-brand-blue" style={{ color: 'var(--blue)' }} />
                </div>
                <div>
                  <div style={{ fontSize: '0.68rem', fontWeight: 700, color: '#8a8f9d', fontFamily: 'var(--font-mono)' }}>EMAIL</div>
                  <div style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--navy)' }}>support@nexaround.com</div>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ width: '38px', height: '38px', borderRadius: '50%', background: 'rgba(26,86,219,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Phone className="w-5 h-5 text-brand-blue" style={{ color: 'var(--blue)' }} />
                </div>
                <div>
                  <div style={{ fontSize: '0.68rem', fontWeight: 700, color: '#8a8f9d', fontFamily: 'var(--font-mono)' }}>PHONE</div>
                  <div style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--navy)' }}>+974 5581 6148</div>
                </div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <div style={{ width: '38px', height: '38px', borderRadius: '50%', background: 'rgba(26,86,219,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Globe className="w-5 h-5 text-brand-blue" style={{ color: 'var(--blue)' }} />
                </div>
                <div>
                  <div style={{ fontSize: '0.68rem', fontWeight: 700, color: '#8a8f9d', fontFamily: 'var(--font-mono)' }}>WEBSITE</div>
                  <div style={{ fontSize: '0.88rem', fontWeight: 600, color: 'var(--navy)' }}>www.nexaround.com</div>
                </div>
              </div>
            </div>
          </div>

        </div>
      </section>

      {/* Why Partner Section */}
      <section style={{ marginTop: '80px', background: 'var(--navy)', color: '#fff', padding: '80px 0' }}>
        <div className="container" style={{ padding: '0 24px' }}>
          <div style={{ textAlign: 'center', maxWidth: '600px', margin: '0 auto 48px' }}>
            <div className="badge badge-orange" style={{ marginBottom: '14px' }}>Why Partner With NexARound?</div>
            <h2 style={{ fontSize: '2rem', fontWeight: 800, color: '#fff', margin: '0 0 12px' }}>
              Your success is our mission
            </h2>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '20px' }} className="grid-2">
            {partnerReasons.map((r, i) => (
              <div key={i} className="dark-card" style={{ padding: '24px 20px', textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '10px' }}>
                <div style={{ fontSize: '0.88rem', fontWeight: 700, color: '#fff' }}>{r.title}</div>
                <p style={{ fontSize: '0.78rem', color: 'rgba(255,255,255,0.6)', lineHeight: 1.6, margin: 0 }}>{r.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

    </div>
  );
}
