import { Fragment } from 'react';
import { NavLink } from 'react-router-dom';
import { NAV_SECTIONS } from '../../nav';
import { LogOutIcon } from '../Icons';

export default function Sidebar({ onLogout }) {
  return (
    <aside className="sidebar">
      <div className="sidebar-logo">
        <span className="logo-tile">
          <img
            src="/logo_2.png"
            alt="nexARound"
            onError={(e) => { e.currentTarget.style.display = 'none'; }}
          />
        </span>
        <div>
          <div className="brand">nexARound</div>
          <div className="brand-sub">ADMIN PORTAL</div>
        </div>
      </div>
      <nav className="sidebar-nav">
        {NAV_SECTIONS.map((section, i) => (
          <Fragment key={section.label}>
            <div className="nav-section-label" style={i > 0 ? { marginTop: '8px' } : undefined}>
              {section.label}
            </div>
            {section.items.map(({ path, label, icon: Icon }) => (
              <NavLink key={path} to={path} className="nav-item">
                <span className="icon"><Icon size={18} /></span> {label}
              </NavLink>
            ))}
          </Fragment>
        ))}
      </nav>
      <div className="sidebar-footer">
        <div className="admin-user">
          <div className="admin-avatar">A</div>
          <div className="user-info" style={{ display: 'flex', flexDirection: 'column', minWidth: 0, flex: 1, gap: '2px' }}>
            <div className="admin-name" title="Admin">Admin</div>
            <div className="admin-role" title="Administrator">Administrator</div>
          </div>
        </div>
        <button className="logout-btn" title="Sign out" onClick={onLogout}>
          <LogOutIcon size={16} />
        </button>
      </div>
    </aside>
  );
}
