// Small pieces the Packages, Reviews and Profile pages share. The CSS they
// rely on is the shared block at the end of index.css. List, filter and form
// pieces live in Lists.jsx and Forms.jsx.

export function Switch({ checked, onChange, label, disabled }) {
  return (
    <label className="switch" onClick={(e) => e.stopPropagation()}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span className="switch-track" />
      {label}
    </label>
  );
}

export function Toast({ toast }) {
  if (!toast) return null;
  return <div className={`xp-toast ${toast.tone === 'error' ? 'error' : ''}`}>{toast.message}</div>;
}

/**
 * A group of related form fields in a soft-coloured panel, with a coloured
 * icon and title. The white inputs stand out against the tint, and each
 * section of a long form gets its own colour so the groups are easy to tell
 * apart. `tone` is one of the .tone-* families in index.css.
 */
export function Section({ tone = 'teal', icon: Icon, title, hint, action, children }) {
  return (
    <section className={`form-section tone-${tone}`}>
      <div className="form-section-head">
        {Icon && <span className="form-section-icon"><Icon size={16} /></span>}
        <div className="form-section-text">
          <div className="form-section-title">{title}</div>
          {hint && <div className="form-section-hint">{hint}</div>}
        </div>
        {action && <div className="form-section-action">{action}</div>}
      </div>
      {children}
    </section>
  );
}

/**
 * Sign-in, set-password and forgot-password share one frame: the brand on the
 * beach photo on one side, the form on the other.
 */
export function AuthLayout({ title, children }) {
  return (
    <div className="auth-page">
      <aside className="auth-brand">
        <div className="auth-brand-inner">
          <span className="logo-tile lg">
            <img src="/logo_2.png" alt="" onError={(e) => { e.currentTarget.style.display = 'none'; }} />
          </span>
          <div>
            <div className="auth-wordmark">nexARound</div>
            <div className="auth-sub">Partner Portal</div>
          </div>
        </div>
      </aside>
      <main className="auth-main">
        <div className="auth-card">
          <h1 className="auth-title">{title}</h1>
          {children}
        </div>
      </main>
    </div>
  );
}

/** One read-only detail (label and value) as a coloured tile. */
export function InfoTile({ tone = 'teal', icon: Icon, label, value, muted }) {
  return (
    <div className={`info-tile tone-${tone}`}>
      {Icon && <span className="info-icon"><Icon size={16} /></span>}
      <div style={{ minWidth: 0 }}>
        <div className="info-label">{label}</div>
        <div className={`info-value ${muted ? 'muted' : ''}`}>{value}</div>
      </div>
    </div>
  );
}
