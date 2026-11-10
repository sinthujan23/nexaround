import { useState, useEffect } from 'react';
import { FileText, ShieldAlert, CheckCircle2, AlertTriangle, Scale, Ban, Sparkles, Smartphone, Mail, MapPin } from 'lucide-react';
import { NavLink } from 'react-router-dom';

const heroBackgrounds = [
  '/bg_pyramids_giza.png',
  '/bg_colosseum_rome.png',
  '/bg_eiffel_tower.png',
  '/bg_sigiriya.png',
  '/bg_taj_mahal.png',
  '/bg_machu_picchu.png',
  '/bg_great_wall.png',
  '/bg_sydney_opera.png',
  '/bg_statue_liberty.png',
];

export default function Terms() {
  const [currentBgIndex, setCurrentBgIndex] = useState(0);

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrentBgIndex((prev) => (prev + 1) % heroBackgrounds.length);
    }, 4500);
    return () => clearInterval(timer);
  }, []);
  return (
    <div style={{ background: '#ffffff', minHeight: '100vh', paddingBottom: '100px' }}>
      
      {/* Header Section */}
      <section className="dark-section" style={{ position: 'relative', padding: '160px 24px 80px', textAlign: 'center', overflow: 'hidden' }}>
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
              backgroundPosition: 'center 35%',
              opacity: idx === currentBgIndex ? 0.45 : 0,
              filter: 'brightness(1.1) contrast(1.05)',
              transform: idx === currentBgIndex ? 'scale(1.03)' : 'scale(1)',
              transition: 'opacity 1.4s ease-in-out, transform 5s ease-out',
              zIndex: 1,
              pointerEvents: 'none'
            }}
          />
        ))}
        <div style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, background: 'rgba(8, 10, 20, 0.75)', zIndex: 1, pointerEvents: 'none' }} />
        <div style={{ position: 'absolute', top: '20%', left: '50%', transform: 'translateX(-50%)', width: '700px', height: '400px', background: 'radial-gradient(ellipse at center, rgba(0, 122, 124, 0.3) 0%, rgba(10, 17, 24, 0) 70%)', pointerEvents: 'none', zIndex: 2 }} />

        <div className="container" style={{ position: 'relative', zIndex: 2 }}>
          <div style={{ maxWidth: '850px', margin: '0 auto' }}>
            <div className="badge badge-teal-glow" style={{ marginBottom: '20px' }}>
              <Scale style={{ width: '14px', height: '14px' }} /> Legal Agreements & EULA
            </div>
            <h1 style={{ fontSize: 'clamp(2.4rem, 5vw, 3.4rem)', fontWeight: 500, color: '#ffffff', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
              Terms of <span className="text-gradient-teal">Service & EULA</span>
            </h1>
            <p style={{ color: 'rgba(255, 255, 255, 0.85)', fontSize: '1.1rem', lineHeight: 1.7, margin: '0 auto 20px', maxWidth: '700px' }}>
              Terms of use and end-user license agreement governing the <strong>NexAround</strong> smart tourism mobile application and services.
            </p>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontSize: '0.85rem', color: 'rgba(255,255,255,0.7)', background: 'rgba(255,255,255,0.08)', padding: '6px 16px', borderRadius: 'var(--radius-pill)', border: '1px solid rgba(255,255,255,0.15)' }}>
              <span>Last Updated: November 2026</span>
              <span>•</span>
              <span>Effective Date: August 2026</span>
            </div>
          </div>
        </div>
      </section>

      {/* Main Content Area */}
      <section className="container" style={{ maxWidth: '960px', margin: '60px auto 0' }}>
        <div className="feature-card" style={{ padding: 'clamp(32px, 5vw, 64px)' }}>

          {/* Section 1: Agreement to Terms */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <FileText style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              1. Agreement to Terms
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
              By accessing, downloading, or using the NexAround mobile application or website, you agree to be bound by these Terms of Service. If you do not agree to these terms, please discontinue use of the platform.
            </p>
          </div>

          {/* Section 2: License Grant */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <CheckCircle2 style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              2. End-User License Grant
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              NexAround grants you a revocable, non-exclusive, non-transferable, limited license to download, install, and use the mobile application strictly for personal, non-commercial travel purposes in accordance with these terms.
            </p>
          </div>

          {/* Section 3: Safety & AR Camera Guidance */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <AlertTriangle style={{ width: '22px', height: '22px', color: '#ffb800' }} />
              3. Spatial AR & Physical Safety Advisory
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
              When using the augmented reality camera and navigation features, you must always maintain awareness of your physical surroundings, traffic, terrain, and local safety rules. Do not operate AR camera modes while walking across busy roadways or hazardous areas.
            </p>
          </div>

          {/* Section 4: Subscriptions */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Scale style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              4. Subscriptions (Voyager & Globetrotter)
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              NexAround has a free plan, Explorer, and two paid plans, Voyager and Globetrotter, each billed monthly or yearly. What each plan includes, such as the number of Odyssey plans a month, Neva messages a day and the AR and map range, is shown on the plans screen in the app before you buy. Plans are for personal use and are subject to fair use.
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              <strong>Payment.</strong> Subscriptions are bought in the app through the Apple App Store or Google Play. Payment is charged to your Apple ID or Google account when you confirm the purchase, at the price the store shows in your currency, including any applicable taxes.
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              <strong>Automatic renewal.</strong> A subscription renews automatically for the same period and at the same price unless you cancel it at least 24 hours before the end of the current period. Your account is charged for the renewal within the 24 hours before the period ends.
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              <strong>Cancelling.</strong> You can cancel or change your plan at any time in your App Store or Google Play subscription settings. Cancelling stops the next renewal; you keep your plan until the end of the period you have paid for, then return to Explorer.
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              <strong>Refunds.</strong> Purchases are processed by Apple or Google, and refunds are handled by them under their own refund policies.
            </p>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '12px' }}>
              <strong>Limits and changes.</strong> Neva message limits reset daily at 00:00 UTC. Odyssey plan limits reset monthly: on the 1st of the month on Explorer, and on your billing date on a paid plan. We may change what a plan includes or its price; a price change takes effect only from a later renewal, after the notice Apple or Google require, and you can cancel before it applies.
            </p>
          </div>

          {/* Contact Section */}
          <div style={{ borderTop: '1px solid var(--border-color)', paddingTop: '32px', textAlign: 'left' }}>
            <h3 style={{ fontSize: '1.2rem', fontWeight: 500, color: 'var(--dark-charcoal)', marginBottom: '10px' }}>Legal Support Contact</h3>
            <p style={{ fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: '0 0 16px' }}>
              For formal legal inquiries, EULA questions, or enterprise terms:
            </p>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <a href="mailto:support@nexaround.com" style={{ color: 'var(--brand-teal)', fontWeight: 500, display: 'inline-flex', alignItems: 'center', gap: '8px' }}>
                <Mail style={{ width: '16px', height: '16px' }} /> support@nexaround.com
              </a>
              <div style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', display: 'inline-flex', alignItems: 'flex-start', gap: '8px' }}>
                <MapPin style={{ width: '16px', height: '16px', color: 'var(--brand-teal)', flexShrink: 0, marginTop: '3px' }} />
                <span>NexAround Technologies, No.47/3/1/1, 4th Lane, Madiwela, Kotte, Colombo, Sri Lanka</span>
              </div>
            </div>
          </div>

        </div>
      </section>

    </div>
  );
}
