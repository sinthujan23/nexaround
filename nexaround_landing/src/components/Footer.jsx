import { NavLink } from 'react-router-dom';
import { Mail, Phone, Globe, ArrowUpRight } from 'lucide-react';

export default function Footer() {
  return (
    <footer style={{ background: 'var(--navy)', borderTop: '1px solid rgba(255, 255, 255, 0.1)', color: '#ffffff', paddingTop: '80px', paddingBottom: '40px' }}>
      <div style={{ maxWidth: '1360px', margin: '0 auto', padding: '0 40px' }}>
        
        {/* Main Footer 4-Column Grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr 1fr 1.2fr', gap: '48px', marginBottom: '64px' }} className="grid-2">
          
          {/* Brand Info Column */}
          <div style={{ textAlign: 'left' }}>
            <NavLink to="/" style={{ display: 'inline-flex', alignItems: 'center', gap: '12px', textDecoration: 'none', marginBottom: '20px' }}>
              <div style={{ width: '38px', height: '38px', borderRadius: '10px', background: '#ffffff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <img src="/tech_logo.png" alt="NexARound Logo" style={{ width: '24px', height: '24px', objectFit: 'contain' }} />
              </div>
              <span style={{ fontSize: '1.2rem', fontWeight: 800, color: '#ffffff' }}>NexARound</span>
            </NavLink>

            <p style={{ fontSize: '0.9rem', color: 'rgba(255, 255, 255, 0.72)', lineHeight: 1.7, margin: '0 0 24px', maxWidth: '340px' }}>
              Full-stack software engineering, custom ERPNext enterprise platforms, AI data engines, and spatial mobile ecosystems tailored for global scale.
            </p>

            <div style={{ fontSize: '0.8rem', color: 'rgba(255,255,255,0.6)', fontWeight: 600, letterSpacing: '0.5px', textTransform: 'uppercase' }}>
              Sri Lanka & Global Engineering Operations
            </div>
          </div>

          {/* Navigation Links Column */}
          <div style={{ textAlign: 'left' }}>
            <h4 style={{ fontSize: '0.78rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1.2px', color: '#ffffff', marginBottom: '20px' }}>Company Navigation</h4>
            <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '12px' }}>
              <li><NavLink to="/" className="footer-link">Home</NavLink></li>
              <li><NavLink to="/services" className="footer-link">Services</NavLink></li>
              <li><NavLink to="/solutions" className="footer-link">Solutions</NavLink></li>
              <li><NavLink to="/app" className="footer-link">Flagship Mobile App</NavLink></li>
              <li><NavLink to="/about" className="footer-link">About Us</NavLink></li>
              <li><NavLink to="/contact" className="footer-link">Contact</NavLink></li>
            </ul>
          </div>

          {/* Solutions Column */}
          <div style={{ textAlign: 'left' }}>
            <h4 style={{ fontSize: '0.78rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1.2px', color: '#ffffff', marginBottom: '20px' }}>Solutions Suite</h4>
            <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '12px' }}>
              <li><NavLink to="/solutions" className="footer-link">ERPNext Business Systems</NavLink></li>
              <li><NavLink to="/solutions" className="footer-link">AI, ML & Data Engines</NavLink></li>
              <li><NavLink to="/solutions" className="footer-link">Blockchain & Web3</NavLink></li>
              <li><NavLink to="/solutions" className="footer-link">Cloud & DevOps Engineering</NavLink></li>
              <li><NavLink to="/app" className="footer-link">nexARound Spatial Platform</NavLink></li>
            </ul>
          </div>

          {/* Contact Column */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <h4 style={{ fontSize: '0.78rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1.2px', color: '#ffffff' }}>Corporate Communications</h4>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '14px', fontSize: '0.88rem' }}>
              <a href="mailto:support@nexaround.com" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'rgba(255, 255, 255, 0.8)', textDecoration: 'none' }}>
                <div style={{ width: '34px', height: '34px', borderRadius: '8px', background: 'rgba(26,86,219,0.15)', border: '1px solid rgba(26,86,219,0.25)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Mail style={{ width: '16px', height: '16px', color: '#60a5fa' }} />
                </div>
                support@nexaround.com
              </a>

              <a href="tel:+97455816148" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'rgba(255, 255, 255, 0.8)', textDecoration: 'none' }}>
                <div style={{ width: '34px', height: '34px', borderRadius: '8px', background: 'rgba(26,86,219,0.15)', border: '1px solid rgba(26,86,219,0.25)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Phone style={{ width: '16px', height: '16px', color: '#60a5fa' }} />
                </div>
                +974 5581 6148
              </a>

              <a href="https://www.nexaround.com" target="_blank" rel="noreferrer" style={{ display: 'flex', alignItems: 'center', gap: '12px', color: 'rgba(255, 255, 255, 0.8)', textDecoration: 'none' }}>
                <div style={{ width: '34px', height: '34px', borderRadius: '8px', background: 'rgba(26,86,219,0.15)', border: '1px solid rgba(26,86,219,0.25)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Globe style={{ width: '16px', height: '16px', color: '#60a5fa' }} />
                </div>
                www.nexaround.com
              </a>
            </div>
          </div>

        </div>

        {/* Bottom Row */}
        <div style={{ borderTop: '1px solid rgba(255, 255, 255, 0.1)', paddingTop: '32px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '0.82rem', color: 'rgba(255, 255, 255, 0.72)', flexWrap: 'wrap', gap: '16px' }}>
          <p style={{ margin: 0 }}>© {new Date().getFullYear()} NexARound Technologies. All rights reserved.</p>

          <div style={{ display: 'flex', gap: '24px' }}>
            <NavLink to="/about" style={{ color: 'rgba(255, 255, 255, 0.72)', textDecoration: 'none' }}>Privacy Policy</NavLink>
            <NavLink to="/about" style={{ color: 'rgba(255, 255, 255, 0.72)', textDecoration: 'none' }}>Terms of Service</NavLink>
          </div>
        </div>

      </div>
    </footer>
  );
}
