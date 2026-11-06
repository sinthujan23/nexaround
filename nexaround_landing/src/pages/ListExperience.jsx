import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { Award, CheckCircle2, Send, ArrowUpRight } from 'lucide-react';
import { COUNTRIES } from '../data/countries';

// The app's "List your experience" form on the website. It sends to the same
// API as the app, so applications land in Admin > Provider applications and
// the support inbox; the team then contacts the business.
const API_URL = 'https://api.nexaround.com/api/v1/experiences/provider-applications';

const EMPTY = {
  business_name: '',
  contact_name: '',
  contact_phone: '',
  contact_email: '',
  country_code: '',
  city: '',
  offering: '',
  links: '',
  website: ''
};

const BENEFITS = [
  'Your experiences appear in the app, for travellers near you and for those browsing your country.',
  'Travellers send a request for their date, and you confirm it or offer another one.',
  'Manage packages, prices, availability and reviews in the app or on the provider portal.',
  'Travellers pay you directly at the experience.'
];

const STEPS = [
  'Send us your details with this form.',
  'Our team contacts you to set up your packages, prices and photos.',
  'Your experiences go live in the nexARound app.'
];

const labelStyle = { display: 'block', fontSize: '0.82rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '6px' };
const hintStyle = { fontSize: '0.78rem', color: 'var(--text-muted)', margin: '6px 0 0' };

// FastAPI says what is wrong as a string, or as a list of field errors.
function messageFrom(detail) {
  if (typeof detail === 'string') return detail;
  if (Array.isArray(detail) && detail[0]?.msg) return String(detail[0].msg).replace(/^Value error, /, '');
  return '';
}

export default function ListExperience() {
  const [form, setForm] = useState(EMPTY);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState('');

  const field = (name) => ({
    value: form[name],
    onChange: (e) => setForm({ ...form, [name]: e.target.value })
  });

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSending(true);
    setError('');
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          business_name: form.business_name.trim(),
          contact_name: form.contact_name.trim(),
          contact_phone: form.contact_phone.trim(),
          contact_email: form.contact_email.trim(),
          country_code: form.country_code,
          city: form.city.trim() || null,
          offering: form.offering.trim(),
          links: form.links.trim() || null,
          source: 'website',
          website: form.website || null
        })
      });
      if (res.ok) {
        setSent(true);
        setForm(EMPTY);
      } else if (res.status === 429) {
        setError('Too many applications from here. Please try again later, or email support@nexaround.com.');
      } else {
        const body = await res.json().catch(() => ({}));
        setError(messageFrom(body.detail) || 'Your details could not be sent. Please check them, or email support@nexaround.com.');
      }
    } catch {
      setError('Your details could not be sent. Please email support@nexaround.com.');
    } finally {
      setSending(false);
    }
  };

  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '100px' }}>

      {/* Header */}
      <section className="dark-section" style={{ position: 'relative', padding: '160px 24px 80px', textAlign: 'center', overflow: 'hidden' }}>
        <div style={{ position: 'absolute', inset: 0, backgroundImage: 'url(/bg_machu_picchu.png)', backgroundSize: 'cover', backgroundPosition: 'center 35%', opacity: 0.45, pointerEvents: 'none' }} />
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(8, 10, 20, 0.75)', pointerEvents: 'none' }} />
        <div className="container" style={{ position: 'relative', zIndex: 2 }}>
          <div style={{ maxWidth: '760px', margin: '0 auto' }}>
            <div className="badge badge-teal-glow" style={{ marginBottom: '20px' }}>
              <Award style={{ width: '14px', height: '14px' }} /> Experience Partners
            </div>
            <h1 style={{ fontSize: 'clamp(2.4rem, 5vw, 3.4rem)', fontWeight: 500, color: '#ffffff', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
              List your <span className="text-gradient-teal">experience</span>
            </h1>
            <p style={{ color: 'rgba(255, 255, 255, 0.85)', fontSize: '1.1rem', lineHeight: 1.7, margin: '0 auto', maxWidth: '640px' }}>
              Run tours, boat trips or activities? Send us your details, and our team will contact you to set up your listing in the nexARound app.
            </p>
          </div>
        </div>
      </section>

      <section className="container" style={{ maxWidth: '1100px', margin: '60px auto 0' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.3fr', gap: '48px', alignItems: 'start' }} className="grid-2">

          {/* Why and how */}
          <div style={{ textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 18px' }}>Why list with nexARound</h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', marginBottom: '36px' }}>
              {BENEFITS.map((b) => (
                <div key={b} style={{ display: 'flex', gap: '10px', alignItems: 'flex-start', fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
                  <CheckCircle2 style={{ width: '18px', height: '18px', color: 'var(--brand-teal)', flexShrink: 0, marginTop: '3px' }} />
                  <span>{b}</span>
                </div>
              ))}
            </div>

            <h2 style={{ fontSize: '1.5rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 18px' }}>How it works</h2>
            <ol style={{ paddingLeft: '22px', margin: '0 0 36px', display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
              {STEPS.map((s) => <li key={s}>{s}</li>)}
            </ol>

            <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
              Already listed?{' '}
              <a href="https://partner.nexaround.com" style={{ color: 'var(--brand-teal)', fontWeight: 500, display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                Open the provider portal <ArrowUpRight style={{ width: '14px', height: '14px' }} />
              </a>
            </p>
          </div>

          {/* Form */}
          <div className="feature-card" style={{ padding: '40px 34px', textAlign: 'left' }}>
            {sent ? (
              <div style={{ background: 'var(--brand-teal-soft)', border: '1px solid rgba(0, 122, 124, 0.3)', borderRadius: '16px', padding: '40px 24px', textAlign: 'center' }}>
                <CheckCircle2 style={{ width: '48px', height: '48px', color: 'var(--brand-teal)', margin: '0 auto 16px' }} />
                <h3 style={{ fontSize: '1.3rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: '0 0 8px' }}>Thank you!</h3>
                <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', margin: '0 0 20px', lineHeight: 1.6 }}>
                  We have your details. Our team will contact you to set up your listing.
                </p>
                <button onClick={() => setSent(false)} className="btn-teal">Send another</button>
              </div>
            ) : (
              <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
                <h3 style={{ fontSize: '1.3rem', fontWeight: 500, color: 'var(--dark-charcoal)', margin: 0 }}>Your details</h3>

                <div>
                  <label htmlFor="le-business" style={labelStyle}>Business name *</label>
                  <input id="le-business" type="text" required minLength={2} maxLength={255} className="form-input" placeholder="e.g. Blue Lagoon Boat Tours" {...field('business_name')} />
                </div>

                <div className="grid-2" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '18px' }}>
                  <div>
                    <label htmlFor="le-name" style={labelStyle}>Your name *</label>
                    <input id="le-name" type="text" required minLength={2} maxLength={120} className="form-input" autoComplete="name" {...field('contact_name')} />
                  </div>
                  <div>
                    <label htmlFor="le-phone" style={labelStyle}>Phone *</label>
                    <input id="le-phone" type="tel" required minLength={6} maxLength={32} className="form-input" autoComplete="tel" placeholder="+44 20 7946 0000" {...field('contact_phone')} />
                    <p style={hintStyle}>Include the country code.</p>
                  </div>
                </div>

                <div>
                  <label htmlFor="le-email" style={labelStyle}>Email *</label>
                  <input id="le-email" type="email" required maxLength={255} className="form-input" autoComplete="email" {...field('contact_email')} />
                </div>

                <div className="grid-2" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '18px' }}>
                  <div>
                    <label htmlFor="le-country" style={labelStyle}>Country *</label>
                    <select id="le-country" required className="form-select" {...field('country_code')}>
                      <option value="" disabled>Choose a country</option>
                      {COUNTRIES.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
                    </select>
                  </div>
                  <div>
                    <label htmlFor="le-city" style={labelStyle}>City or town</label>
                    <input id="le-city" type="text" maxLength={120} className="form-input" {...field('city')} />
                  </div>
                </div>

                <div>
                  <label htmlFor="le-offer" style={labelStyle}>What do you offer? *</label>
                  <textarea id="le-offer" required minLength={10} maxLength={3000} rows="4" className="form-textarea" placeholder="e.g. Sunset boat trips and snorkelling, about 3 hours, for up to 12 people" {...field('offering')} />
                </div>

                <div>
                  <label htmlFor="le-links" style={labelStyle}>Links</label>
                  <input id="le-links" type="text" maxLength={1000} className="form-input" placeholder="Instagram, Google Maps, website" {...field('links')} />
                  <p style={hintStyle}>You can add a link to a folder of your photos, such as Google Drive.</p>
                </div>

                {/* Hidden from people; only a bot fills it in. */}
                <div style={{ position: 'absolute', left: '-9999px' }} aria-hidden="true">
                  <label>
                    Leave this empty
                    <input type="text" tabIndex={-1} autoComplete="off" {...field('website')} />
                  </label>
                </div>

                {error && <p role="alert" style={{ color: '#C0392B', fontSize: '0.9rem', margin: 0 }}>{error}</p>}

                <button type="submit" disabled={sending} className="btn-teal" style={{ width: '100%', justifyContent: 'center', marginTop: '6px', opacity: sending ? 0.7 : 1 }}>
                  <Send style={{ width: '16px', height: '16px' }} />
                  <span>{sending ? 'Sending…' : 'Send my details'}</span>
                </button>
                <p style={{ ...hintStyle, textAlign: 'center' }}>
                  We use these details only to contact you about listing your experiences. See our{' '}
                  <NavLink to="/privacy" style={{ color: 'var(--brand-teal)' }}>Privacy Policy</NavLink>.
                </p>
              </form>
            )}
          </div>
        </div>
      </section>
    </div>
  );
}
