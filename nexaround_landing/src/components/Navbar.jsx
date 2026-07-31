import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { Menu, X, ArrowRight } from 'lucide-react';

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  const navItems = [
    { name: 'Home', path: '/' },
    { name: 'Services', path: '/services' },
    { name: 'Solutions', path: '/solutions' },
    { name: 'About', path: '/about' },
    { name: 'Contact', path: '/contact' },
  ];

  return (
    <header className="navbar-header">
      <div className="container navbar-container" style={{ height: '100%', padding: '0 24px' }}>
        
        {/* Logo */}
        <NavLink to="/" className="logo-link">
          <img 
            src="/tech_logo.png" 
            alt="NexARound Technologies Logo" 
            style={{ width: '34px', height: '34px', objectFit: 'contain' }} 
          />
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span className="brand-title" style={{ fontSize: '0.9rem', lineHeight: 1.2 }}>
              NexARound
            </span>
            <span style={{ fontSize: '0.55rem', color: 'var(--text-muted)', fontWeight: 600, letterSpacing: '1.5px', textTransform: 'uppercase' }}>
              Technologies
            </span>
          </div>
        </NavLink>

        {/* Desktop Nav */}
        <nav className="desktop-nav" style={{ display: 'flex', gap: '8px' }}>
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => `desktop-nav-link ${isActive ? 'active' : ''}`}
              style={({ isActive }) => ({
                fontSize: '0.8rem',
                fontWeight: 600,
                padding: '6px 14px',
                borderRadius: '9999px',
                color: isActive ? 'var(--blue)' : 'var(--text-secondary)',
                background: isActive ? 'rgba(26, 86, 219, 0.08)' : 'transparent',
                transition: 'all 0.25s ease'
              })}
            >
              {item.name}
            </NavLink>
          ))}
        </nav>

        {/* CTA */}
        <div className="desktop-cta" style={{ display: 'flex', alignItems: 'center' }}>
          <NavLink to="/contact" className="btn-primary" style={{ padding: '8px 16px', fontSize: '0.78rem', borderRadius: '9999px' }}>
            Get in Touch <ArrowRight style={{ width: '14px', height: '14px' }} />
          </NavLink>
        </div>

        {/* Mobile Toggle */}
        <button
          onClick={() => setMobileOpen(!mobileOpen)}
          className="mobile-toggle btn-secondary"
          style={{ padding: '8px 12px', borderRadius: '9999px' }}
          aria-label="Toggle Menu"
        >
          {mobileOpen ? <X style={{ width: '18px', height: '18px' }} /> : <Menu style={{ width: '18px', height: '18px' }} />}
        </button>
      </div>

      {/* Mobile Drawer */}
      {mobileOpen && (
        <div className="mobile-nav-drawer" style={{
          display: 'block', position: 'absolute', top: '72px', left: 0, width: '100%',
          background: '#fff', borderBottom: '1px solid var(--border-color)',
          borderRadius: '24px', padding: '20px 24px', boxShadow: 'var(--shadow-md)', zIndex: 90
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            {navItems.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={() => setMobileOpen(false)}
                className={({ isActive }) => `desktop-nav-link ${isActive ? 'active' : ''}`}
                style={{ display: 'block', textAlign: 'center' }}
              >
                {item.name}
              </NavLink>
            ))}
            <div style={{ paddingTop: '12px', borderTop: '1px solid var(--border-color)', marginTop: '8px' }}>
              <NavLink to="/contact" onClick={() => setMobileOpen(false)} className="btn-primary" style={{ width: '100%', justifyContent: 'center' }}>
                Get in Touch
              </NavLink>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
