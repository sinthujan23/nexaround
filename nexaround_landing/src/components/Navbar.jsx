import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { Menu, X, ArrowRight } from 'lucide-react';

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  const navItems = [
    { name: 'Home', path: '/' },
    { name: 'Services', path: '/services' },
    { name: 'Solutions', path: '/solutions' },
    { name: 'Flagship App', path: '/app' },
    { name: 'About', path: '/about' },
    { name: 'Contact', path: '/contact' },
  ];

  return (
    <header className="navbar-header">
      <div style={{ maxWidth: '1360px', margin: '0 auto', height: '100%', padding: '0 40px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        
        {/* Left: Brand Mark Container */}
        <NavLink to="/" className="logo-link" style={{ display: 'flex', alignItems: 'center', gap: '14px', textDecoration: 'none' }}>
          <div style={{ 
            width: '42px', 
            height: '42px', 
            borderRadius: '12px', 
            background: '#ffffff', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center',
            boxShadow: '0 4px 16px rgba(0, 0, 0, 0.25)',
            border: '1px solid rgba(255, 255, 255, 0.9)'
          }}>
            <img 
              src="/tech_logo.png" 
              alt="NexARound Technologies Logo" 
              style={{ width: '28px', height: '28px', objectFit: 'contain' }} 
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontSize: '1.2rem', fontWeight: 800, color: '#ffffff', letterSpacing: '-0.02em', lineHeight: 1.1 }}>
              NexARound
            </span>
            <span style={{ fontSize: '0.62rem', color: '#60a5fa', fontWeight: 700, letterSpacing: '1.8px', textTransform: 'uppercase' }}>
              Technologies
            </span>
          </div>
        </NavLink>

        {/* Center: Desktop Navigation Links */}
        <nav className="desktop-nav" style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => `qatar-nav-link ${isActive ? 'active' : ''}`}
            >
              {item.name}
            </NavLink>
          ))}
        </nav>

        {/* Right CTA Button */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          
          <NavLink to="/contact" className="btn-white-pill" style={{ padding: '12px 26px', fontSize: '0.88rem' }}>
            Get in Touch <ArrowRight style={{ width: '16px', height: '16px' }} />
          </NavLink>

          {/* Mobile Toggle Button */}
          <button
            onClick={() => setMobileOpen(!mobileOpen)}
            className="mobile-toggle"
            style={{ 
              padding: '9px 13px', 
              borderRadius: '10px', 
              background: 'rgba(255, 255, 255, 0.1)', 
              border: '1px solid rgba(255, 255, 255, 0.2)',
              color: '#ffffff',
              cursor: 'pointer'
            }}
            aria-label="Toggle Navigation Menu"
          >
            {mobileOpen ? <X style={{ width: '20px', height: '20px' }} /> : <Menu style={{ width: '20px', height: '20px' }} />}
          </button>

        </div>

      </div>

      {/* Mobile Menu Drawer */}
      {mobileOpen && (
        <div className="mobile-nav-drawer" style={{
          display: 'block', position: 'absolute', top: '78px', left: 0, width: '100%',
          background: 'rgba(10, 22, 40, 0.98)', borderBottom: '1px solid rgba(255, 255, 255, 0.15)',
          padding: '28px 24px', boxShadow: '0 25px 50px rgba(0, 0, 0, 0.6)', zIndex: 90
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
            {navItems.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={() => setMobileOpen(false)}
                className={({ isActive }) => `qatar-nav-link ${isActive ? 'active' : ''}`}
                style={{ display: 'block', textAlign: 'center', fontSize: '1.05rem', padding: '10px 0' }}
              >
                {item.name}
              </NavLink>
            ))}
            <div style={{ paddingTop: '16px', borderTop: '1px solid rgba(255, 255, 255, 0.15)', marginTop: '8px' }}>
              <NavLink to="/contact" onClick={() => setMobileOpen(false)} className="btn-white-pill" style={{ width: '100%', justifyContent: 'center' }}>
                Get in Touch <ArrowRight style={{ width: '16px', height: '16px' }} />
              </NavLink>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
