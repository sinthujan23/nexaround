import { FileText, ShieldAlert, CheckCircle2, AlertTriangle, Scale, Ban, Sparkles, Smartphone, Mail } from 'lucide-react';
import { NavLink } from 'react-router-dom';

export default function Terms() {
  return (
    <div style={{ paddingBottom: '100px' }}>
      
      {/* Header Section */}
      <section style={{ textAlign: 'center', maxWidth: '960px', margin: '0 auto', padding: '150px 24px 48px', position: 'relative' }}>
        <div className="badge badge-blue" style={{ margin: '0 auto 20px' }}>
          <Scale style={{ width: '14px', height: '14px' }} /> Legal Agreements & EULA
        </div>
        <h1 style={{ fontSize: 'clamp(2.4rem, 5vw, 3.4rem)', fontWeight: 800, color: 'var(--navy)', margin: '0 0 16px', lineHeight: 1.15, letterSpacing: '-0.025em' }}>
          Terms of <span className="text-gradient-blue">Service & EULA</span>
        </h1>
        <p style={{ color: 'var(--text-secondary)', fontSize: '1.1rem', lineHeight: 1.7, margin: '0 auto 16px', maxWidth: '700px' }}>
          Terms of use, end-user license agreement, and community standards for NexARound Technologies and the <strong>NexAround</strong> mobile application.
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

          {/* Section 1: Agreement to Terms */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <FileText style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              1. Agreement to Terms
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              These Terms of Service and End User License Agreement ("Terms", "Agreement") constitute a legally binding agreement between you ("User", "you") and <strong>NexARound Technologies</strong> ("Company", "we", "us", or "our") concerning your access to and use of the <a href="https://nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>nexaround.com</a> website, associated web portals, and our flagship mobile application, <strong>NexAround</strong> (the "App").
            </p>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              By downloading, installing, accessing, or using our App and Website, you acknowledge that you have read, understood, and agreed to be bound by these Terms and our <NavLink to="/privacy" style={{ color: 'var(--blue)', fontWeight: 600 }}>Privacy Policy</NavLink>. If you do not agree with all of these terms, you are expressly prohibited from using the services and must discontinue use immediately.
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 2: End User License Agreement (EULA) */}
          <div style={{ marginBottom: '40px' }}>
            <div className="badge badge-teal" style={{ marginBottom: '14px' }}>
              <Smartphone style={{ width: '13px', height: '13px' }} /> App Store End User License Agreement (EULA)
            </div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px' }}>
              2. Mobile App License & Usage Rights
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              Subject to your compliance with these Terms, NexARound Technologies grants you a revocable, non-exclusive, non-transferable, limited license to download, install, and use the <strong>NexAround</strong> mobile application on personal iOS (Apple) and Android devices owned or controlled by you, solely for personal, non-commercial travel, tourism, and exploration purposes.
            </p>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              You agree not to decompile, reverse engineer, disassemble, attempt to derive the source code of, modify, or create derivative works of the App, any updates, or any part thereof (except to the extent permitted by applicable law).
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 3: User Generated Content & Strict Community Policy (Apple Guideline 1.2 Compliance) */}
          <div style={{ marginBottom: '40px' }}>
            <div className="badge badge-orange" style={{ marginBottom: '14px' }}>
              <ShieldAlert style={{ width: '13px', height: '13px' }} /> Apple Guideline 1.2 Compliance
            </div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px' }}>
              3. User-Generated Content (UGC) & Zero-Tolerance Policy
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              The NexAround App provides interactive features, such as <strong>Travel Stories</strong>, journals, and community comments, allowing users to upload travel media, tips, and experiences.
            </p>
            
            <div style={{ background: 'rgba(232, 119, 34, 0.08)', border: '1px solid rgba(232, 119, 34, 0.25)', borderRadius: 'var(--radius-md)', padding: '24px', marginBottom: '20px' }}>
              <h4 style={{ fontSize: '1.1rem', fontWeight: 800, color: 'var(--orange)', marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <Ban style={{ width: '20px', height: '20px' }} /> Zero Tolerance for Objectionable Content and Abusive Users
              </h4>
              <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                NexARound Technologies strictly prohibits and enforces zero tolerance for objectionable, offensive, unlawful, defamatory, harassing, sexually explicit, hateful, or abusive content. There is no tolerance for harassment or discrimination of any kind.
              </p>
            </div>

            <h4 style={{ fontSize: '1.05rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '10px' }}>
              User Safety, Reporting, and Moderation Commitments:
            </h4>
            <ul style={{ paddingLeft: '24px', color: 'var(--text-secondary)', lineHeight: 1.8, display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <li><strong>In-App Reporting:</strong> Users can flag/report any objectionable travel story, photo, or comment immediately using the in-app report button.</li>
              <li><strong>User Blocking:</strong> Users can block any account whose content or interactions they find unwelcome. Blocked accounts will be immediately hidden from your view.</li>
              <li><strong>24-Hour Action Guarantee:</strong> Our moderation team investigates all user reports and will remove objectionable content and eject/ban offending accounts within 24 hours of notification.</li>
            </ul>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />          {/* Section 4: AR Navigation & Real-World Safety */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <AlertTriangle style={{ width: '22px', height: '22px', color: 'var(--orange)' }} />
              4. Augmented Reality (AR) & Real-World Safety Warning
            </h2>
            <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)' }}>
              <p style={{ fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.7, margin: 0 }}>
                <strong>Always prioritize physical safety:</strong> When using NexAround’s AR camera mode and GPS navigation, remain aware of your immediate physical surroundings, traffic, pedestrian crossings, terrain hazards, and local laws. Never operate AR features while driving or operating machinery. NexARound Technologies is not liable for accidents or property damage resulting from inattention to real-world surroundings.
              </p>
            </div>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 5: AI Companion (Neva) Information Disclaimer */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Sparkles style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              5. AI Companion (Neva) Information Disclaimer
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              Recommendations, historical commentary, museum routes, and travel tips provided by Neva (our spatial AI companion) are generated using artificial intelligence for informational and entertainment purposes. While we strive for accuracy, business opening hours, ticket pricing, transit schedules, and route conditions may change. Users are encouraged to verify critical details with official venue operators.
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 6: Intellectual Property */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px' }}>
              6. Intellectual Property Rights
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              The NexAround trademarks, brand assets, UI designs, algorithms, codebases, audio-visual materials, and databases are the exclusive proprietary property of <strong>NexARound Technologies</strong> and are protected by international copyright, trademark, and intellectual property laws.
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 7: Limitation of Liability */}
          <div style={{ marginBottom: '40px' }}>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px' }}>
              7. Disclaimer of Warranties & Limitation of Liability
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              The services and app are provided on an "AS IS" and "AS AVAILABLE" basis without warranties of any kind, whether express or implied. In no event will NexARound Technologies, its directors, employees, or partners be liable for any indirect, consequential, exemplary, incidental, special, or punitive damages arising from your use of the app or website.
            </p>
          </div>

          <hr style={{ border: 'none', borderTop: '1px solid var(--border-color)', margin: '36px 0' }} />

          {/* Section 8: Contact Information */}
          <div>
            <h2 style={{ fontSize: '1.5rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              <Mail style={{ width: '22px', height: '22px', color: 'var(--blue)' }} />
              8. Contact Us
            </h2>
            <p style={{ color: 'var(--text-secondary)', lineHeight: 1.8, marginBottom: '14px' }}>
              If you have any questions about these Terms of Service or need to report a terms violation, please contact:
            </p>
            <div style={{ background: 'var(--bg-light)', padding: '20px', borderRadius: 'var(--radius-sm)', border: '1px solid var(--border-color)', fontSize: '0.95rem', color: 'var(--text-secondary)', lineHeight: 1.8 }}>
              <strong>NexARound Technologies</strong><br />
              Attn: Legal & Compliance Team<br />
              Email: <a href="mailto:support@nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>support@nexaround.com</a><br />
              Website: <a href="https://www.nexaround.com" style={{ color: 'var(--blue)', fontWeight: 600 }}>www.nexaround.com</a>
            </div>
          </div>

        </div>
      </section>

    </div>
  );
}
