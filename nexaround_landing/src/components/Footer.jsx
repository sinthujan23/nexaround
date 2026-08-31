import { NavLink, useNavigate, useLocation } from 'react-router-dom';
import { Mail, Globe } from 'lucide-react';
import StoreButtons from './StoreButtons';

export default function Footer() {
  const navigate = useNavigate();
  const location = useLocation();

  const handleNavClick = (path, hash) => (e) => {
    e.preventDefault();
    if (hash) {
      if (location.pathname === path) {
        const elem = document.querySelector(hash);
        if (elem) {
          elem.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      } else {
        navigate(`${path}${hash}`);
        setTimeout(() => {
          const elem = document.querySelector(hash);
          if (elem) {
            elem.scrollIntoView({ behavior: 'smooth', block: 'start' });
          }
        }, 120);
      }
    } else {
      if (location.pathname === path) {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      } else {
        navigate(path);
      }
    }
  };

  return (
    <footer style={{ background: 'var(--dark-charcoal)', borderTop: '1px solid rgba(0, 122, 124, 0.25)', color: '#ffffff', paddingTop: '80px', paddingBottom: '40px', position: 'relative' }}>
      <div className="container">
        
        {/* Main Footer Grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1.5fr 1fr 1fr 1.2fr', gap: '48px', marginBottom: '64px' }} className="footer-grid">
          
          {/* Brand Info Column */}
          <div style={{ textAlign: 'left' }}>
            <NavLink to="/" onClick={handleNavClick('/', null)} style={{ display: 'inline-flex', alignItems: 'center', gap: '12px', textDecoration: 'none', marginBottom: '20px' }}>
              <div style={{ 
                width: '40px', 
                height: '40px', 
                borderRadius: '12px', 
                background: '#ffffff', 
                display: 'flex', 
                alignItems: 'center', 
                justifyContent: 'center',
                boxShadow: '0 4px 16px rgba(0, 0, 0, 0.25)',
                padding: '4px'
              }}>
                <img src="/logo_2.png" alt="NexAround Logo" style={{ width: '30px', height: '30px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.src = '/app_icon.png'; }} />
              </div>
              <span style={{ fontSize: '1.35rem', fontWeight: 900, color: '#ffffff', letterSpacing: '-0.03em' }}>NexAround</span>
            </NavLink>

            <p style={{ fontSize: '0.92rem', color: 'rgba(255, 255, 255, 0.75)', lineHeight: 1.7, margin: '0 0 24px', maxWidth: '340px' }}>
              The next-generation AI & Augmented Reality smart tourism companion. Discover landmarks, generate custom Odyssey itineraries, and explore with your 24/7 AI travel concierge.
            </p>

            {/* Store Download Badges */}
            <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
              <StoreButtons theme="onDark" direction="row" align="flex-start" showRating={false} />
            </div>
          </div>

          {/* App Feature Modules */}
          <div style={{ textAlign: 'left' }}>
            <h4 style={{ fontSize: '0.8rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1.2px', color: '#00d2d3', marginBottom: '20px' }}>App Modules</h4>
            <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <li>
                <a href="/app#odyssey" onClick={handleNavClick('/app', '#odyssey')} className="footer-link">
                  Odyssey Trip Planner
                </a>
              </li>
              <li>
                <a href="/app#camera" onClick={handleNavClick('/app', '#camera')} className="footer-link">
                  AR Landmark Scanner
                </a>
              </li>
              <li>
                <a href="/app#neva" onClick={handleNavClick('/app', '#neva')} className="footer-link">
                  Neva 24/7 AI Concierge
                </a>
              </li>
              <li>
                <a href="/app#radar" onClick={handleNavClick('/app', '#radar')} className="footer-link">
                  Around You Proximity Radar
                </a>
              </li>
              <li>
                <a href="/app#museum" onClick={handleNavClick('/app', '#museum')} className="footer-link">
                  Curated Museum Guides
                </a>
              </li>
              <li>
                <a href="/app#stories" onClick={handleNavClick('/app', '#stories')} className="footer-link">
                  Travel Stories & Journal
                </a>
              </li>
            </ul>
          </div>

          {/* Quick Links */}
          <div style={{ textAlign: 'left' }}>
            <h4 style={{ fontSize: '0.8rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1.2px', color: '#00d2d3', marginBottom: '20px' }}>Quick Links</h4>
            <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <li>
                <a href="/" onClick={handleNavClick('/', null)} className="footer-link">
                  Home
                </a>
              </li>
              <li>
                <a href="/app" onClick={handleNavClick('/app', null)} className="footer-link">
                  App Features
                </a>
              </li>
              <li>
                <a href="/services" onClick={handleNavClick('/services', null)} className="footer-link">
                  Services
                </a>
              </li>
              <li>
                <a href="/solutions" onClick={handleNavClick('/solutions', null)} className="footer-link">
                  Solutions
                </a>
              </li>
              <li>
                <a href="/about" onClick={handleNavClick('/about', null)} className="footer-link">
                  About
                </a>
              </li>
            </ul>
          </div>

          {/* Contact Details */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <h4 style={{ fontSize: '0.8rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1.2px', color: '#00d2d3' }}>Connect</h4>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <a href="mailto:support@nexaround.com" className="footer-connect-link" style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '12px', textDecoration: 'none' }}>
                <div className="footer-icon-box" style={{ width: '36px', height: '36px', borderRadius: '10px', background: 'rgba(0, 122, 124, 0.2)', border: '1px solid rgba(0, 122, 124, 0.35)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, transition: 'all 0.25s ease' }}>
                  <Mail style={{ width: '16px', height: '16px', color: '#00d2d3' }} />
                </div>
                <span style={{ fontSize: '0.92rem', color: 'rgba(255, 255, 255, 0.88)' }}>support@nexaround.com</span>
              </a>

              <a href="https://nexaround.com" target="_blank" rel="noreferrer" className="footer-connect-link" style={{ display: 'flex', flexDirection: 'row', alignItems: 'center', gap: '12px', textDecoration: 'none' }}>
                <div className="footer-icon-box" style={{ width: '36px', height: '36px', borderRadius: '10px', background: 'rgba(0, 122, 124, 0.2)', border: '1px solid rgba(0, 122, 124, 0.35)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, transition: 'all 0.25s ease' }}>
                  <Globe style={{ width: '16px', height: '16px', color: '#00d2d3' }} />
                </div>
                <span style={{ fontSize: '0.92rem', color: 'rgba(255, 255, 255, 0.88)' }}>nexaround.com</span>
              </a>
            </div>
          </div>

        </div>

        {/* Bottom Row */}
        <div style={{ borderTop: '1px solid rgba(255, 255, 255, 0.1)', paddingTop: '32px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '0.85rem', color: 'rgba(255, 255, 255, 0.65)', flexWrap: 'wrap', gap: '16px' }}>
          <p style={{ margin: 0 }}>© {new Date().getFullYear()} NexAround Technologies. All rights reserved.</p>

          <div style={{ display: 'flex', gap: '24px' }}>
            <NavLink to="/privacy" className="footer-link" style={{ fontSize: '0.85rem' }}>Privacy Policy</NavLink>
            <NavLink to="/terms" className="footer-link" style={{ fontSize: '0.85rem' }}>Terms of Service</NavLink>
          </div>
        </div>

      </div>
    </footer>
  );
}
