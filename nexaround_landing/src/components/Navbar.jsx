import { useState } from 'react';
import { NavLink } from 'react-router-dom';
import { Menu, X, Smartphone } from 'lucide-react';

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  const navItems = [
    { name: 'Home', path: '/' },
    { name: 'App Features', path: '/app' },
    { name: 'Services', path: '/services' },
    { name: 'Solutions', path: '/solutions' },
    { name: 'About', path: '/about' },
    { name: 'Contact', path: '/contact' },
  ];

  return (
    <header className="navbar-header">
      <div className="navbar-container" style={{ maxWidth: '1320px', margin: '0 auto', height: '100%', padding: '0 32px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        
        {/* Left: Brand Logo & Title */}
        <NavLink to="/" style={{ display: 'flex', alignItems: 'center', gap: '12px', textDecoration: 'none' }}>
          <div style={{ 
            width: '42px', 
            height: '42px', 
            borderRadius: '12px', 
            background: '#ffffff', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center',
            boxShadow: '0 4px 16px rgba(0, 0, 0, 0.25)',
            padding: '4px'
          }}>
            <img 
              src="/logo_2.png" 
              alt="NexAround Logo" 
              style={{ width: '32px', height: '32px', objectFit: 'contain' }} 
              onError={(e) => { e.currentTarget.src = '/app_icon.png'; }}
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontSize: '1.28rem', fontWeight: 900, color: '#ffffff', letterSpacing: '-0.03em', lineHeight: 1.1 }}>
              NexAround
            </span>
            <span style={{ fontSize: '0.65rem', color: '#00d2d3', fontWeight: 700, letterSpacing: '1.2px', textTransform: 'uppercase' }}>
              Smart Tourism AI & AR
            </span>
          </div>
        </NavLink>

        {/* Center: Desktop Navigation */}
        <nav className="desktop-nav" style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
          {navItems.map((item) => (
            <NavLink
              key={item.path}
              to={item.path}
              className={({ isActive }) => `nav-link-item ${isActive ? 'active' : ''}`}
            >
              {item.name}
            </NavLink>
          ))}
        </nav>

        {/* Right CTA Button -> Navigates to /get-app */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px' }}>
          
          <NavLink 
            to="/get-app" 
            className="btn-teal" 
            style={{ padding: '10px 22px', fontSize: '0.88rem', textDecoration: 'none' }}
          >
            <Smartphone style={{ width: '16px', height: '16px' }} />
            <span>Get App</span>
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
            aria-label="Toggle Menu"
          >
            {mobileOpen ? <X style={{ width: '20px', height: '20px' }} /> : <Menu style={{ width: '20px', height: '20px' }} />}
          </button>

        </div>

      </div>

      {/* Mobile Navigation Drawer */}
      {mobileOpen && (
        <div style={{
          position: 'absolute',
          top: '80px',
          left: 0,
          width: '100%',
          background: 'rgba(10, 17, 24, 0.98)',
          borderBottom: '1px solid rgba(0, 122, 124, 0.3)',
          padding: '24px 28px',
          boxShadow: '0 25px 50px rgba(0, 0, 0, 0.8)',
          zIndex: 99
        }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {navItems.map((item) => (
              <NavLink
                key={item.path}
                to={item.path}
                onClick={() => setMobileOpen(false)}
                className={({ isActive }) => `nav-link-item ${isActive ? 'active' : ''}`}
                style={{ textAlign: 'left', padding: '12px 18px', fontSize: '1rem' }}
              >
                {item.name}
              </NavLink>
            ))}
            <div style={{ paddingTop: '16px', borderTop: '1px solid rgba(255, 255, 255, 0.12)', marginTop: '6px' }}>
              <NavLink
                to="/get-app"
                onClick={() => setMobileOpen(false)}
                className="btn-teal"
                style={{ width: '100%', justifyContent: 'center', textDecoration: 'none' }}
              >
                <Smartphone style={{ width: '18px', height: '18px' }} /> Download NexAround
              </NavLink>
            </div>
          </div>
        </div>
      )}
    </header>
  );
}
