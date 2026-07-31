import { NavLink } from 'react-router-dom';
import { Mail, Phone, Globe, ArrowRight } from 'lucide-react';

export default function Footer() {
  return (
    <footer style={{ background: 'var(--navy)', color: 'rgba(255,255,255,0.7)', marginTop: '0' }}>
      
      {/* Main Footer */}
      <div className="container" style={{ padding: '56px 24px 40px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr 1fr 1fr', gap: '32px', paddingBottom: '40px', borderBottom: '1px solid rgba(255,255,255,0.08)' }}>
          
          {/* Brand */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '14px' }}>
            <NavLink to="/" style={{ display: 'flex', alignItems: 'center', gap: '10px', textDecoration: 'none' }}>
              <img 
                src="/tech_logo.png" 
                alt="NexARound Technologies Logo" 
                style={{ width: '34px', height: '34px', objectFit: 'contain' }} 
              />
              <div>
                <div style={{ fontSize: '1rem', fontWeight: 800, color: '#fff' }}>NexARound</div>
                <div style={{ fontSize: '0.58rem', color: 'rgba(255,255,255,0.5)', fontWeight: 600, letterSpacing: '1.5px', textTransform: 'uppercase' }}>Technologies</div>
              </div>
            </NavLink>
            <p style={{ fontSize: '0.8rem', lineHeight: 1.6, color: 'rgba(255,255,255,0.5)', margin: 0 }}>
              Full-stack engineering to fast-track your growth. Tailored digital solutions across Sri Lanka and beyond.
            </p>
          </div>

          {/* Navigation */}
          <div style={{ textAlign: 'left' }}>
            <h4 style={{ fontSize: '0.68rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: '#fff', marginBottom: '14px' }}>Company</h4>
            <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '0.82rem' }}>
              <li><NavLink to="/" style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none' }}>Home</NavLink></li>
              <li><NavLink to="/services" style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none' }}>Services</NavLink></li>
              <li><NavLink to="/solutions" style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none' }}>Solutions</NavLink></li>
              <li><NavLink to="/about" style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none' }}>About Us</NavLink></li>
              <li><NavLink to="/contact" style={{ color: 'rgba(255,255,255,0.5)', textDecoration: 'none' }}>Contact</NavLink></li>
            </ul>
          </div>

          {/* Solutions */}
          <div style={{ textAlign: 'left' }}>
            <h4 style={{ fontSize: '0.68rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: '#fff', marginBottom: '14px' }}>Solutions</h4>
            <ul style={{ listStyle: 'none', padding: 0, margin: 0, display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '0.82rem', color: 'rgba(255,255,255,0.5)' }}>
              <li>ERPNext & Business</li>
              <li>AI, ML & Data</li>
              <li>Blockchain & Web3</li>
              <li>Cloud & DevOps</li>
              <li>nexARound App</li>
            </ul>
          </div>

          {/* Contact */}
          <div style={{ textAlign: 'left', display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <h4 style={{ fontSize: '0.68rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '1px', color: '#fff' }}>Contact</h4>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '0.82rem' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'rgba(255,255,255,0.5)' }}>
                <Mail style={{ width: '14px', height: '14px', color: 'var(--blue-light)' }} />
                support@nexaround.com
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'rgba(255,255,255,0.5)' }}>
                <Phone style={{ width: '14px', height: '14px', color: 'var(--blue-light)' }} />
                +974 5581 6148
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px', color: 'rgba(255,255,255,0.5)' }}>
                <Globe style={{ width: '14px', height: '14px', color: 'var(--blue-light)' }} />
                www.nexaround.com
              </div>
            </div>
          </div>
        </div>

        {/* Bottom */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', paddingTop: '24px', fontSize: '0.73rem', color: 'rgba(255,255,255,0.3)' }}>
          <p style={{ margin: 0 }}>© {new Date().getFullYear()} NexARound Technologies. All rights reserved.</p>
          <div style={{ display: 'flex', gap: '16px' }}>
            <NavLink to="/about" style={{ color: 'rgba(255,255,255,0.3)', textDecoration: 'none' }}>Privacy Policy</NavLink>
            <NavLink to="/about" style={{ color: 'rgba(255,255,255,0.3)', textDecoration: 'none' }}>Terms of Service</NavLink>
          </div>
        </div>
      </div>
    </footer>
  );
}
