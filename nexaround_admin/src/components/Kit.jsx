import { useEffect, useState } from 'react';
import { CrossIcon, SearchIcon, EyeIcon, EyeOffIcon, WifiOffIcon, AlertTriangleIcon, RefreshIcon, CheckIcon } from './Icons';

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

/** A whole page or container that could not load. Renders a polished industry-standard error/offline state. */
export function PageError({
  children,
  error,
  title,
  onRetry,
  inline = false,
  style,
}) {
  const [retrying, setRetrying] = useState(false);
  const [copied, setCopied] = useState(false);
  const [showDetails, setShowDetails] = useState(false);

  // Extract human-readable error text
  const rawError = error || (typeof children === 'string' ? children : '');
  const displayMsg =
    typeof children === 'string' && children.length > 0
      ? children
      : String(rawError || 'An error occurred while loading');

  // Detect if this is an offline or network error
  const isOffline = typeof navigator !== 'undefined' && !navigator.onLine;
  const isNetwork =
    isOffline ||
    /failed to fetch|network|offline|load failed|internet|connection|refused|timeout|err_/i.test(
      displayMsg
    );

  const handleRetry = async () => {
    setRetrying(true);
    try {
      if (onRetry) {
        await onRetry();
      } else {
        window.location.reload();
      }
    } finally {
      setTimeout(() => setRetrying(false), 600);
    }
  };

  const handleCopy = () => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(displayMsg);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  if (inline) {
    return (
      <div
        className={`page-error-inline ${isNetwork ? 'page-error-inline-network' : ''}`}
        style={style}
        role="alert"
      >
        <div className="page-error-inline-icon">
          {isNetwork ? <WifiOffIcon size={16} /> : <AlertTriangleIcon size={16} />}
        </div>
        <div className="page-error-inline-content">
          <div className="page-error-inline-msg">{displayMsg}</div>
        </div>
        {onRetry && (
          <button
            type="button"
            className="page-error-inline-btn"
            onClick={handleRetry}
            disabled={retrying}
            title="Try again"
          >
            <RefreshIcon size={13} className={retrying ? 'spin-anim' : ''} />
            <span>{retrying ? 'Retrying...' : 'Retry'}</span>
          </button>
        )}
      </div>
    );
  }

  const headingText =
    title ||
    (isNetwork ? 'Unable to Connect to Server' : 'Unable to Load Content');
  const explanation = isNetwork
    ? 'nexAround could not reach the server. This happens when internet connectivity is unavailable or the backend is temporarily unreachable. Auto-reconnect will resume once connection is restored.'
    : 'A problem occurred while retrieving information. Please try again or refresh the page.';

  return (
    <div className="page-error-wrapper" style={style}>
      <div className="page-error-card">
        {/* Animated Status Pill */}
        <div className={`page-error-badge ${isNetwork ? 'badge-network' : 'badge-server'}`}>
          <span className="page-error-status-dot" />
          <span>{isNetwork ? (isOffline ? 'Offline Mode' : 'Connection Lost') : 'Service Issue'}</span>
        </div>

        {/* Center Icon Box with Pulsing Glow */}
        <div className={`page-error-icon-box ${isNetwork ? 'icon-box-network' : 'icon-box-server'}`}>
          <div className="page-error-icon-halo" />
          {isNetwork ? <WifiOffIcon size={34} /> : <AlertTriangleIcon size={34} />}
        </div>

        {/* Title & Description */}
        <h2 className="page-error-title">{headingText}</h2>
        <p className="page-error-description">{explanation}</p>

        {/* Network Troubleshooting Checklist */}
        {isNetwork && (
          <div className="page-error-tips">
            <div className="page-error-tip-item">
              <span className="tip-bullet">•</span>
              <span>Check your Wi-Fi, Ethernet, or mobile data connection</span>
            </div>
            <div className="page-error-tip-item">
              <span className="tip-bullet">•</span>
              <span>Pages will automatically refresh as soon as your connection is back</span>
            </div>
          </div>
        )}

        {/* Action Buttons */}
        <div className="page-error-actions">
          <button
            type="button"
            className="btn btn-primary page-error-btn-primary"
            onClick={handleRetry}
            disabled={retrying}
          >
            <RefreshIcon size={15} className={retrying ? 'spin-anim' : ''} />
            <span>{retrying ? 'Connecting...' : 'Retry Connection'}</span>
          </button>

          <button
            type="button"
            className="btn btn-ghost page-error-btn-secondary"
            onClick={() => window.location.reload()}
          >
            Reload Page
          </button>
        </div>

        {/* Collapsible Diagnostic Details */}
        <div className="page-error-diagnostic-wrap">
          <button
            type="button"
            className="page-error-diagnostic-toggle"
            onClick={() => setShowDetails(!showDetails)}
          >
            <span>{showDetails ? 'Hide technical details' : 'Show technical details'}</span>
          </button>

          {showDetails && (
            <div className="page-error-diagnostic-box">
              <div className="diagnostic-header">
                <span>Diagnostic message</span>
                <button type="button" className="diagnostic-copy-btn" onClick={handleCopy}>
                  {copied ? 'Copied!' : 'Copy'}
                </button>
              </div>
              <code className="diagnostic-code">{displayMsg}</code>
            </div>
          )}
        </div>
      </div>
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
