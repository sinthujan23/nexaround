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
    <footer className="site-footer">
      <div className="container">
        
        {/* Main Footer Grid (4-Col Desktop, 2-Col Mobile) */}
        <div className="footer-grid">
          
          {/* Brand Info Column */}
          <div className="footer-brand-col">
            <NavLink to="/" onClick={handleNavClick('/', null)} style={{ display: 'inline-flex', alignItems: 'center', gap: '12px', textDecoration: 'none', marginBottom: '18px' }}>
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
                <img src="/logo_2.png" alt="nexARound Logo" style={{ width: '30px', height: '30px', objectFit: 'contain' }} onError={(e) => { e.currentTarget.src = '/app_icon.png'; }} />
              </div>
              <span style={{ fontSize: '1.35rem', fontWeight: 500, color: '#ffffff', letterSpacing: '-0.03em' }}>nexARound</span>
            </NavLink>

            <p style={{ fontSize: '0.92rem', color: 'rgba(255, 255, 255, 0.75)', lineHeight: 1.7, margin: '0 0 22px', maxWidth: '340px' }}>
              The next-generation AI & Augmented Reality smart tourism companion. Discover landmarks, generate custom Odyssey itineraries, and explore with your 24/7 AI travel concierge.
            </p>

            {/* Store Download Badges */}
            <div style={{ display: 'flex', justifyContent: 'flex-start', marginBottom: '8px' }}>
              <StoreButtons theme="onDark" direction="row" align="flex-start" showRating={false} />
            </div>
          </div>

          {/* App Feature Modules Column */}
          <div className="footer-col">
            <h4>App Modules</h4>
            <ul className="footer-links-list">
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

          {/* Quick Links Column */}
          <div className="footer-col">
            <h4>Quick Links</h4>
            <ul className="footer-links-list">
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
                  About Us
                </a>
              </li>
            </ul>
          </div>

          {/* Connect Details Column */}
          <div className="footer-col footer-connect-col">
            <h4>Connect</h4>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <a href="mailto:support@nexaround.com" className="footer-connect-link">
                <div className="footer-icon-box">
                  <Mail style={{ width: '16px', height: '16px', color: '#00d2d3' }} />
                </div>
                <span>support@nexaround.com</span>
              </a>

              <a href="https://nexaround.com" target="_blank" rel="noreferrer" className="footer-connect-link">
                <div className="footer-icon-box">
                  <Globe style={{ width: '16px', height: '16px', color: '#00d2d3' }} />
                </div>
                <span>nexaround.com</span>
              </a>
            </div>
          </div>

        </div>

        {/* Divider */}
        <div className="site-footer-divider" />

        {/* Brand Copyright Line */}
        <p className="site-footer-copy">
          © {new Date().getFullYear()} NexAround Technologies. All rights reserved.
        </p>

        {/* Bottom Legal Links */}
        <div className="site-footer-bottom">
          <div className="site-footer-legal">
            <NavLink to="/privacy" className="footer-link" style={{ fontSize: '0.85rem' }}>Privacy Policy</NavLink>
            <NavLink to="/terms" className="footer-link" style={{ fontSize: '0.85rem' }}>Terms of Service</NavLink>
          </div>
        </div>

      </div>
    </footer>
  );
}
