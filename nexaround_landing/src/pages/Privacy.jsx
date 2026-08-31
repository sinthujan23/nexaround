import { useState, useEffect } from 'react';
import { ShieldCheck, Lock, Eye, FileText, Database, UserCheck, RefreshCw, Mail, Sparkles, Smartphone, Globe } from 'lucide-react';
import { NavLink } from 'react-router-dom';

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

export default function Privacy() {
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
              <ShieldCheck style={{ width: '14px', height: '14px' }} /> Legal & Data Protection
            </div>
            <h1 style={{ fontSize: 'clamp(2.4rem, 5vw, 3.4rem)', fontWeight: 900, color: '#ffffff', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
              Privacy <span className="text-gradient-teal">Policy</span>
            </h1>
            <p style={{ color: 'rgba(255, 255, 255, 0.85)', fontSize: '1.1rem', lineHeight: 1.7, margin: '0 auto 20px', maxWidth: '700px' }}>
              How NexAround collects, protects, and handles your data across our platforms and the <strong>NexAround</strong> smart tourism mobile application.
            </p>
            <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontSize: '0.85rem', color: 'rgba(255,255,255,0.7)', background: 'rgba(255,255,255,0.08)', padding: '6px 16px', borderRadius: 'var(--radius-pill)', border: '1px solid rgba(255,255,255,0.15)' }}>
              <span>Last Updated: August 2026</span>
              <span>•</span>
              <span>Effective Date: August 2026</span>
            </div>
          </div>
        </div>
      </section>

      {/* Main Content Area */}
      <section className="container" style={{ maxWidth: '960px', margin: '60px auto 0' }}>
        <div className="feature-card" style={{ padding: 'clamp(32px, 5vw, 64px)' }}>

          {/* Quick Summary Card */}
          <div style={{ 
            background: 'var(--brand-teal-soft)', 
            border: '1px solid rgba(0, 122, 124, 0.25)', 
            borderRadius: 'var(--radius-md)', 
            padding: '28px 32px', 
            marginBottom: '48px',
            textAlign: 'left'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '12px' }}>
              <Lock style={{ width: '20px', height: '20px', color: 'var(--brand-teal)' }} />
              <h3 style={{ fontSize: '1.15rem', fontWeight: 800, color: 'var(--dark-charcoal)', margin: 0 }}>Privacy Summary & Commitment</h3>
            </div>
            <p style={{ fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.65, margin: 0 }}>
              NexAround is engineered with a strict <strong>Privacy-by-Design</strong> architecture. We do not sell or broker your personal location data. Camera vision landmark scans are processed on-device or ephemerally in volatile memory without retaining private imagery.
            </p>
          </div>

          {/* Section 1: Information We Collect */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Database style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              1. Information We Collect
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, marginBottom: '14px' }}>
              We collect information to provide and optimize the NexAround mobile application and services:
            </p>
            <ul style={{ paddingLeft: '24px', fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.8, display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <li><strong>Account Credentials:</strong> Name, email address, profile picture (via Firebase Authentication).</li>
              <li><strong>Precise Location Data:</strong> GPS coordinates requested strictly with foreground permissions to power the Around You radar and Odyssey route navigation.</li>
              <li><strong>Camera & Sensor Input:</strong> Live camera feeds used strictly during active AR camera mode to identify historical landmarks.</li>
              <li><strong>Travel Logs & Preferences:</strong> Saved itineraries, journal stamps, and dietary preferences specified for Neva AI suggestions.</li>
            </ul>
          </div>

          {/* Section 2: How We Use Your Data */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Eye style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              2. How We Use Your Information
            </h2>
            <ul style={{ paddingLeft: '24px', fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.8, display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <li>Generating optimized multi-day travel itineraries via Odyssey.</li>
              <li>Real-time visual landmark identification and historical overlay rendering.</li>
              <li>Personalized conversational recommendations through Neva AI.</li>
              <li>Detecting proximity attractions and authentic dining options on the living map.</li>
            </ul>
          </div>

          {/* Section 3: Data Security */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Lock style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              3. Data Security & Storage
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
              All network communication between the NexAround mobile client and backend APIs is encrypted using TLS 1.3 encryption. Passwords and sensitive authentication tokens are managed by Firebase Security.
            </p>
          </div>

          {/* Section 4: Data Retention & Account Deletion */}
          <div style={{ marginBottom: '40px', textAlign: 'left' }}>
            <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--dark-charcoal)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <RefreshCw style={{ width: '22px', height: '22px', color: 'var(--brand-teal)' }} />
              4. Data Retention & Account Deletion
            </h2>
            <p style={{ fontSize: '0.96rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
              You may request deletion of your account and associated data directly in the app under <strong>Profile › Delete Account</strong> or by emailing <a href="mailto:support@nexaround.com" style={{ color: 'var(--brand-teal)', fontWeight: 600, textDecoration: 'underline' }}>support@nexaround.com</a>. Deletion requests are permanently processed within 30 days.
            </p>
          </div>

          {/* Contact Section */}
          <div style={{ borderTop: '1px solid var(--border-color)', paddingTop: '32px', textAlign: 'left' }}>
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, color: 'var(--dark-charcoal)', marginBottom: '10px' }}>Contact Privacy Officer</h3>
            <p style={{ fontSize: '0.94rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: '0 0 16px' }}>
              If you have any questions or data deletion requests, please contact our Data Protection team:
            </p>
            <a href="mailto:support@nexaround.com" style={{ color: 'var(--brand-teal)', fontWeight: 700, display: 'inline-flex', alignItems: 'center', gap: '8px' }}>
              <Mail style={{ width: '16px', height: '16px' }} /> support@nexaround.com
            </a>
          </div>

        </div>
      </section>

    </div>
  );
}
