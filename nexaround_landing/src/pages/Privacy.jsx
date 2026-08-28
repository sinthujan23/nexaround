import { ShieldCheck, Lock, Eye, FileText, Database, UserCheck, RefreshCw, Mail, Sparkles, Smartphone, Globe } from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function Privacy() {
  return (
    <div style={{ paddingBottom: '100px' }}>
      
      {/* Header Section */}
      <section style={{ textAlign: 'center', maxWidth: '960px', margin: '0 auto', padding: '150px 24px 48px', position: 'relative' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 20px' }}>
          <ShieldCheck style={{ width: '14px', height: '14px' }} /> Legal & Data Protection
        </div>
        <h1 style={{ fontSize: 'clamp(2.4rem, 5vw, 3.4rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
          Privacy <span className="text-gradient-blue">Policy</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.1rem', lineHeight: 1.7, margin: '0 auto 16px', maxWidth: '700px' }}>
          How NexARound Technologies collects, protects, and handles your data across our corporate platforms and our flagship mobile application, <strong>NexAround</strong>.
        </p>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontSize: '0.88rem', color: 'var(--text-muted)', background: 'var(--bg-light)', padding: '6px 16px', borderRadius: 'var(--radius-pill)', border: '1px solid var(--border-color)' }}>
          <span>Last Updated: August 2026</span>
          <span>•</span>
          <span>Effective Date: August 2026</span>
        </div>
      </section>

      {/* Main Content Area */}
      <section className="container" style={{ maxWidth: '960px', margin: '0 auto' }}>
        <div style={{ 
          background: 'var(--bg-white)', 
          border: '1px solid var(--border-color)', 
          borderRadius: 'var(--radius-lg)', 
          padding: 'clamp(32px, 5vw, 64px)', 
          boxShadow: 'var(--shadow-md)' 
        }}>

          {/* Quick Summary Card */}
          <div style={{ 
            background: 'linear-gradient(135deg, rgba(26,86,219,0.05) 0%, rgba(0,122,124,0.05) 100%)', 
            border: '1px solid rgba(26,86,219,0.18)', 
            borderRadius: 'var(--radius-md)', 
            padding: '24px 28px', 
            marginBottom: '48px' 
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '12px' }}>
              <Sparkles style={{ width: '20px', height: '20px', color: 'var(--blue)' }} />
              <h3 style={{ fontSize: '1.15rem', fontWeight: 700, margin: 0, color: 'var(--navy)' }}>Privacy Highlights at a Glance</h3>
            </div>
            <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
              NexARound Technologies respects your privacy. We never sell your personal data or continuous camera feeds to third-party data brokers. Camera, microphone, and precise geolocation features in the <strong>NexAround</strong> mobile app are used strictly to provide live AR recognition, real-time spatial navigation, and personalized AI travel assistance.
            </p>
          </div>

          {/* Section 1: Introduction */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Globe style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              1. About Us & Scope of this Policy
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              This Privacy Policy applies to <strong>NexARound Technologies</strong> ("Company", "we", "our", or "us"), our official website (<a href="https://nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>nexaround.com</a>), enterprise software services, and our flagship mobile application, <strong>NexAround</strong> (available on the Apple App Store and Google Play).
            </p>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              This document outlines how we collect, process, store, and safeguard your personal information when you visit our website, communicate with our team, or utilize the features within the NexAround mobile application.
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 2: Mobile App Specific Permissions */}
          <div style={{ marginBottom: '40px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '14px' }}>
              <Smartphone style={{ width: '13px', height: '13px' }} /> Flagship App Specific Disclosures
            </div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px' }}>
              2. NexAround Mobile App: Device Permissions & Data Use
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '20px' }}>
              To deliver augmented reality (AR) guidance, intelligent navigation, and context-aware travel companionship, the NexAround mobile app requests the following device permissions:
            </p>

            <div style={{ display: 'grid', gap: '18px' }}>
              
              <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)' }}>
                <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>
                  📷 Camera & Augmented Reality (AR) Mode
                </h4>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                  <strong>Purpose:</strong> Used exclusively when you open the AR exploration tool to identify monuments, historical landmarks, museums, and points of interest in real time using on-device machine vision and spatial intelligence.<br />
                  <strong>Data Handling:</strong> Camera feeds are processed in real-time frame buffers. We <em>do not</em> record, harvest, or store continuous personal video streams or facial biometric data on our servers.
                </p>
              </div>

              <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)' }}>
                <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>
                  📍 Precise Geolocation (GPS) & Spatial Maps
                </h4>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                  <strong>Purpose:</strong> Used while the app is active to pinpoint nearby attractions, calculate walking routes, display tailored itineraries, and orient AR directional tags.<br />
                  <strong>Data Handling:</strong> Location coordinates are used to query our spatial backend and map providers (Google Maps Platform / Mapbox). We do not track your location in the background when the app is terminated, nor do we sell location telemetry to advertisers.
                </p>
              </div>

              <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)' }}>
                <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>
                  🎙️ Microphone & Speech Recognition
                </h4>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                  <strong>Purpose:</strong> Requested only when you tap the voice search option or record voice notes/videos for personal travel journals.<br />
                  <strong>Data Handling:</strong> Audio is converted to text tokens using native speech APIs and is never listened to or used for marketing profiling.
                </p>
              </div>

              <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)' }}>
                <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>
                  🔮 AI Travel Companion (Neva)
                </h4>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                  <strong>Purpose:</strong> Enables context-aware recommendations, local culinary guides, historical facts, and custom itinerary generation.<br />
                  <strong>Data Handling:</strong> Text prompts you send to Neva are transmitted securely to advanced language model processors (such as Google Gemini API) to generate immediate responses. We do not use your private personal messages to train public foundational AI models.
                </p>
              </div>

              <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)' }}>
                <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '6px' }}>
                  📸 User-Generated Content & Travel Stories
                </h4>
                <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>
                  <strong>Purpose:</strong> When you share a Travel Story or journal entry, your uploaded photos and text captions are stored on our secure cloud database so they can be viewed by the community.<br />
                  <strong>Control:</strong> You maintain full control to edit or delete your posted stories at any time from within the app.
                </p>
              </div>

            </div>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 3: Information We Collect Across Services */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Database style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              3. Information We Collect
            </h2>
            <ul style={{ paddingLeft: '24px', color: 'var(--text-secondary)', lineHeight: 1.8, display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <li><strong>Account Credentials:</strong> Name, email address, profile avatar, and authentication tokens provided when signing up via Email, Google Sign-In, or Sign in with Apple.</li>
              <li><strong>Usage & Diagnostics:</strong> App session metrics, crash diagnostics, device model, operating system version, and feature interaction metrics used to fix bugs and improve stability.</li>
              <li><strong>Corporate Website Inquiries:</strong> Contact information, company name, and project requirements submitted through our contact and consultation forms.</li>
            </ul>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 4: Third-Party Service Providers */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Lock style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              4. Third-Party Service Providers
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              We partner with trusted, SOC-2 compliant technology infrastructure providers to deliver our services:
            </p>
            <ul style={{ paddingLeft: '24px', color: 'var(--text-secondary)', lineHeight: 1.8, display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <li><strong>Authentication & Cloud Infrastructure:</strong> Google Firebase (Authentication, Cloud Messaging) & Amazon Web Services / VPS cloud hosts.</li>
              <li><strong>Maps & Geocoding:</strong> Google Maps Platform and Mapbox Maps SDK.</li>
              <li><strong>Generative AI Intelligence:</strong> Google Generative AI (Gemini API) & Anthropic.</li>
              <li><strong>External Bookings & Deep Links:</strong> Third-party travel services (e.g., Booking.com, Uber) when you explicitly initiate external reservations.</li>
            </ul>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 5: Data Retention & Account Deletion */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <UserCheck style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              5. Your Rights & Account Deletion
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              In compliance with Apple App Store Review Guidelines, GDPR, and CCPA standards, you have the right to access, export, or permanently erase your personal data.
            </p>
            <div style={{ background: 'rgba(232,119,34,0.06)', border: '1px solid rgba(232,119,34,0.25)', borderRadius: 'var(--radius-sm)', padding: '20px' }}>
              <h4 style={{ fontSize: '1rem', fontWeight: 700, color: 'var(--orange)', marginBottom: '8px' }}>
                How to Delete Your Account & Associated Data:
              </h4>
              <p style={{ fontSize: '0.92rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                1. <strong>In-App:</strong> Open the NexAround App ➔ Navigate to <strong>Profile / Settings</strong> ➔ Select <strong>Delete Account</strong>.<br />
                2. <strong>Email Request:</strong> Send an email from your registered address to <a href="mailto:support@nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>support@nexaround.com</a> with the subject line <em>"Account Deletion Request"</em>. All associated profile data, saved itineraries, and travel stories will be permanently deleted within 30 days.
              </p>
            </div>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 6: Security & Policy Updates */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <RefreshCw style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              6. Security & Policy Updates
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              We implement enterprise-grade encryption in transit (HTTPS/TLS 1.3) and at rest (AES-256). While no digital method is 100% infallible, we continuously monitor and patch our systems against vulnerabilities.
            </p>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              We may update this Privacy Policy from time to time to reflect technological or regulatory changes. Updated versions will be posted on this page with an updated "Effective Date."
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 7: Contact Us */}
          <div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Mail style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              7. Contact Privacy Team
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              If you have any questions, concerns, or requests regarding this Privacy Policy or your data, please contact our legal and privacy officers:
            </p>
            <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)', fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              <strong>NexARound Technologies</strong><br />
              Attn: Data Privacy & Compliance Officer<br />
              Email: <a href="mailto:support@nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>support@nexaround.com</a><br />
              Website: <a href="https://www.nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>www.nexaround.com</a>
            </div>
          </div>

        </div>
      </section>

    </div>
  );
}
