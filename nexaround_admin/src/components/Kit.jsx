import { useEffect, useState } from 'react';
import { CrossIcon, SearchIcon, EyeIcon, EyeOffIcon } from './Icons';

// Small pieces every admin page shares. Each one renders the same markup and
// classes the pages used to write out by hand, so swapping one in changes no
// pixels. The partner portal has its own Kit.jsx with the same Switch, Drawer
// and Toast.

/** A white card, optionally with a title row and an action on its right. */
export function Card({ title, action, children, className = '', style }) {
  return (
    <div className={`card ${className}`.trim()} style={style}>
      {(title || action) && (
        <div className="card-header">
          <div className="card-title">{title}</div>
          {action}
        </div>
      )}
      {children}
    </div>
  );
}

const STAT_CHANGE_WITH_ICON = { display: 'inline-flex', alignItems: 'center', gap: '4px' };

/**
 * One KPI tile in a .stats-grid. `trend` colours the change pill ('up',
 * 'down', or null for a pill styled through `changeStyle`).
 */
export function StatCard({
  icon: Icon, iconColor = 'var(--accent)', value, label,
  change, trend = 'up', changeIcon: ChangeIcon, changeStyle,
}) {
  return (
    <div className="stat-card">
      <div className="stat-icon"><Icon size={24} style={{ color: iconColor }} /></div>
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
      {change != null && (
        <span
          className={trend ? `stat-change ${trend}` : 'stat-change'}
          style={ChangeIcon ? { ...STAT_CHANGE_WITH_ICON, ...changeStyle } : changeStyle}
        >
          {ChangeIcon ? <><ChangeIcon size={12} /> {change}</> : change}
        </span>
      )}
    </div>
  );
}

/** The teal gradient banner at the top of a page. `large` is the dashboard's. */
export function HeroBanner({ title, titleSize, large, action, children }) {
  return (
    <div className="approvals-hero" style={{
      background: 'linear-gradient(135deg, var(--accent) 0%, var(--accent-2) 100%)',
      borderRadius: '16px',
      padding: large ? '20px 24px' : '16px 24px',
      color: 'white',
      marginBottom: large ? '24px' : '16px',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center',
      boxShadow: '0 8px 24px rgba(0, 122, 124, 0.12)'
    }}>
      <div>
        <h2 style={{ fontSize: `${titleSize || (large ? 24 : 20)}px`, fontWeight: 800, margin: 0, letterSpacing: '-0.5px' }}>{title}</h2>
        <p style={{ margin: large ? '6px 0 0 0' : '4px 0 0 0', opacity: 0.9, fontSize: large ? '14px' : '13px', fontWeight: 500 }}>
          {children}
        </p>
      </div>
      {action}
    </div>
  );
}

/** The highlighted number inside a HeroBanner sentence. */
export function HeroCount({ children }) {
  return (
    <strong style={{ color: '#fff', background: 'rgba(255,255,255,0.2)', padding: '2px 8px', borderRadius: '12px' }}>
      {children}
    </strong>
  );
}

/** The white button on the right of a HeroBanner. */
export function HeroButton({ onClick, children }) {
  return (
    <button className="btn" onClick={onClick} style={{
      background: 'white',
      color: 'var(--accent)',
      padding: '10px 20px',
      borderRadius: '10px',
      fontWeight: 800,
      fontSize: '13px',
      boxShadow: '0 4px 14px rgba(0,0,0,0.1)'
    }}>
      {children}
    </button>
  );
}

/** A centred dialog with a title and a close button. Escape closes it. */
export function Modal({ title, onClose, maxWidth, children }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()} style={maxWidth ? { maxWidth } : undefined}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
          <h3 style={{ fontSize: '18px', fontWeight: 800 }}>{title}</h3>
          <button type="button" className="btn btn-ghost" style={{ padding: '6px', borderRadius: '50%' }} onClick={onClose} title="Close">
            <CrossIcon size={16} />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

/** A form panel that slides in from the right, keeping the page in view. */
export function Drawer({ title, subtitle, onClose, footer, children, onSubmit }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const Body = onSubmit ? 'form' : 'div';
  return (
    <div className="drawer-overlay" onClick={onClose}>
      <Body className="drawer" onClick={(e) => e.stopPropagation()} onSubmit={onSubmit}>
        <div className="drawer-head">
          <div>
            <div className="drawer-title">{title}</div>
            {subtitle && <div className="drawer-sub">{subtitle}</div>}
          </div>
          <button type="button" className="icon-btn" onClick={onClose} title="Close">
            <CrossIcon size={18} />
          </button>
        </div>
        <div className="drawer-body">{children}</div>
        <div className="drawer-foot">{footer}</div>
      </Body>
    </div>
  );
}

export function Switch({ checked, onChange, label, disabled }) {
  return (
    <label className="switch" onClick={(e) => e.stopPropagation()}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span className="switch-track" />
      {label}
    </label>
  );
}

/** Pairs with useToast() from hooks.js. */
export function Toast({ toast }) {
  if (!toast) return null;
  return <div className={`xp-toast ${toast.tone === 'error' ? 'error' : ''}`}>{toast.message}</div>;
}

/**
 * The dashed "nothing here" panel. With a title the children are the line
 * under it; without one they are the whole message.
 */
export function EmptyState({ icon, title, children, style }) {
  return (
    <div className="empty-state" style={style}>
      {icon && <div className="empty-icon">{icon}</div>}
      {title ? (
        <>
          <h3 style={{ margin: '0 0 4px 0', fontSize: '16px', color: 'var(--text-primary)' }}>{title}</h3>
          {children && <p style={{ margin: 0, fontSize: '13px' }}>{children}</p>}
        </>
      ) : children}
    </div>
  );
}

/** A spinner with a line of text, in the empty-state panel. */
export function Loading({ children }) {
  return (
    <div className="empty-state">
      <div className="loader"></div>
      <p>{children}</p>
    </div>
  );
}

/** A whole page still loading its first data: a centred spinner, no text. */
export function PageLoading() {
  return (
    <div
      role="status"
      aria-label="Loading"
      style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: '50vh' }}
    >
      <div className="loader" style={{ width: '32px', height: '32px', margin: 0 }}></div>
    </div>
  );
}

/** A whole page that could not load. */
export function PageError({ children }) {
  return (
    <div className="login-error" style={{ margin: '20px' }}>
      {children}
    </div>
  );
}

export function SearchBar({ value, onChange, placeholder, icon = true, style }) {
  return (
    <div className="search-bar" style={style}>
      {icon && <SearchIcon size={16} style={{ color: 'var(--text-secondary)' }} />}
      <input type="text" placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}

/** tone: green | yellow | red | blue | ghost */
export function Badge({ tone, children, style, title }) {
  return <span className={tone ? `badge badge-${tone}` : 'badge'} style={style} title={title}>{children}</span>;
}

/** A text input whose value is masked until the eye button is pressed. */
export function SecretField({ label, tag, value, onChange, placeholder, required }) {
  const [show, setShow] = useState(false);
  return (
    <div className="form-group" style={{ marginBottom: '16px' }}>
      <label className="form-label">
        {label}{' '}
        {tag && <span style={{ fontSize: '11px', color: 'var(--accent)', fontWeight: 700 }}>{tag}</span>}
      </label>
      <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
        <input
          type="text"
          className="form-input"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          autoComplete="off"
          required={required}
          style={{ paddingRight: '46px', WebkitTextSecurity: show ? 'none' : 'disc' }}
        />
        <button
          type="button"
          onClick={() => setShow(!show)}
          title={show ? 'Hide' : 'Show'}
          style={{
            position: 'absolute', right: '12px', background: 'none',
            border: 'none', cursor: 'pointer', color: 'var(--text-secondary)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '4px',
          }}
        >
          {show ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
        </button>
      </div>
    </div>
  );
}
