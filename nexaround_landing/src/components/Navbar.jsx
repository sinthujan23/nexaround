import { useState, useEffect } from 'react';
import { NavLink, useLocation } from 'react-router-dom';
import { Menu, X, Smartphone } from 'lucide-react';

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const location = useLocation();

  useEffect(() => {
    const handleScroll = () => {
      if (window.scrollY > 20) {
        setScrolled(true);
      } else {
        setScrolled(false);
      }
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  // Close mobile drawer on route change
  useEffect(() => {
    setMobileOpen(false);
  }, [location.pathname, location.hash]);

  const navItems = [
    { name: 'Home', path: '/' },
    { name: 'App Features', path: '/app' },
    { name: 'Services', path: '/services' },
    { name: 'Solutions', path: '/solutions' },
    { name: 'About', path: '/about' },
  ];

  return (
    <header className={`navbar-header ${scrolled ? 'navbar-scrolled' : ''}`}>
      <div className="navbar-inner-wrapper">
        
        {/* Left: Brand Logo & Title */}
        <NavLink to="/" className="nav-brand-group">
          <div className="nav-brand-logo-box">
            <img 
              src="/logo_2.png" 
              alt="NexAround" 
              className="nav-brand-logo-img"
              onError={(e) => { e.currentTarget.src = '/app_icon.png'; }}
            />
          </div>

          <div className="nav-brand-text-col">
            <div className="nav-brand-title">
              <span className="brand-bold">nexARound</span>
            </div>
            <span className="nav-brand-subtitle" style={{ color: '#00d2d3', letterSpacing: '1.2px' }}>
              SMART TOURISM AI & AR
            </span>
          </div>
        </NavLink>

        {/* Center: Frosted Glass Pill Capsule Navigation */}
        <nav className="desktop-nav nav-capsule">
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => `nav-capsule-item ${isActive ? 'active' : ''}`}
            >
              {item.name}
            </NavLink>
          ))}
        </nav>

        {/* Right: Get App Button & Mobile Toggle */}
        <div className="nav-right-actions">
          
          <NavLink 
            to="/get-app" 
            className="btn-get-app-pill"
          >
            <Smartphone size={16} />
            <span>Get App</span>
          </NavLink>

          {/* Mobile Toggle Button */}
          <button
            onClick={() => setMobileOpen(!mobileOpen)}
            className="mobile-toggle-btn"
            aria-label="Toggle Menu"
          >
            {mobileOpen ? <X size={20} /> : <Menu size={20} />}
          </button>

        </div>

      </div>

      {/* Mobile Navigation Drawer */}
      {mobileOpen && (
        <div className="mobile-nav-drawer">
          <div className="mobile-nav-links">
            {navItems.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={() => setMobileOpen(false)}
                className={({ isActive }) => `mobile-nav-item ${isActive ? 'active' : ''}`}
              >
                {item.name}
              </NavLink>
            ))}
            <div className="mobile-nav-cta-wrap">
              <NavLink
                to="/get-app"
                onClick={() => setMobileOpen(false)}
                className="btn-get-app-pill mobile-cta-btn"
              >
                <Smartphone size={18} />
                <span>Get App</span>
              </NavLink>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
