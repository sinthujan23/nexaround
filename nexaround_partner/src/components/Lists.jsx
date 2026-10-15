import { Link } from 'react-router-dom';
import { SearchIcon } from './Icons';
import { STATUS_LABELS, STATUS_TONES } from '../format';

// The list-and-filter pieces the Dashboard, Packages, Enquiries and Security
// pages each rebuilt for themselves.

export function Loader() {
  return <div className="loader" />;
}

export function ErrorBanner({ children }) {
  if (!children) return null;
  return <div className="login-error">{children}</div>;
}

/**
 * "Nothing here" and "nothing matches". `card` puts it on its own white card,
 * for a page's main area; without it, it sits inside a panel or a list pane.
 */
export function EmptyState({ icon: Icon, title, children, action, card = false, pad = 32 }) {
  return (
    <div className={`${card ? 'card ' : ''}xp-empty`} style={{ padding: pad }}>
      {Icon && <Icon size={card ? 36 : 32} />}
      <strong>{title}</strong>
      {children}
      {action && <div style={{ marginTop: 12 }}>{action}</div>}
    </div>
  );
}

/** Previous, "Page x of y", Next. Renders nothing when there is one page. */
export function Pagination({ page, totalPages, onPage, className = '' }) {
  if (totalPages <= 1) return null;
  return (
    <div className={`pager ${className}`}>
      <button type="button" className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => onPage(page - 1)}>
        Previous
      </button>
      <span>Page {page} of {totalPages}</span>
      <button type="button" className="btn btn-ghost btn-sm" disabled={page >= totalPages} onClick={() => onPage(page + 1)}>
        Next
      </button>
    </div>
  );
}

/**
 * Filter buttons: `items` is `[{ value, label, count?, dot? }]`. This is for
 * narrowing a list; `TabNav` below is for moving between pages.
 */
export function Tabs({ items, value, onChange }) {
  return (
    <div className="seg" role="tablist">
      {items.map((item) => (
        <button
          key={item.value || 'all'} type="button" role="tab" aria-selected={value === item.value}
          className={`seg-btn ${value === item.value ? 'active' : ''}`}
          onClick={() => onChange(item.value)}
        >
          {item.dot && <span className={`dot dot-${item.dot}`} />}
          {item.label}
          {item.count != null && <span className="seg-count">{item.count}</span>}
        </button>
      ))}
    </div>
  );
}

export function SearchInput({ value, onChange, placeholder }) {
  return (
    <div className="search-bar">
      <SearchIcon size={16} />
      <input type="text" value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} />
    </div>
  );
}

export function StatusPill({ tone = 'gray', children, title }) {
  return <span className={`pill tone-${tone}`} title={title}>{children}</span>;
}

export function EnquiryStatusPill({ status }) {
  return (
    <StatusPill tone={STATUS_TONES[status] || 'gray'}>{STATUS_LABELS[status] || status}</StatusPill>
  );
}

/**
 * One row: a lead (avatar, thumbnail or icon), a title, one or more small
 * lines, and something on the right. `variant` picks the stylesheet family -
 * `dash` (dashboard panels), `xp` (the enquiries list) or `sec` (security) -
 * so all three share one structure without their looks changing.
 *
 * With `to` it is a real link (middle-click and "open in new tab" work), with
 * `onClick` a button, otherwise a plain row.
 */
export function ListRow({
  variant = 'dash', to, onClick, active, lead, title, strong, subs = [], side, className = '',
}) {
  const body = (
    <>
      {lead}
      <div className={`${variant}-row-main`}>
        <div className={`${variant}-row-title ${strong ? 'strong' : ''}`}>{title}</div>
        {[].concat(subs).filter(Boolean).map((sub, i) => (
          <div key={i} className={`${variant}-row-sub`}>{sub}</div>
        ))}
      </div>
      {side && <div className={`${variant}-row-side`}>{side}</div>}
    </>
  );
  const cls = `${variant}-row ${active ? 'active' : ''} ${className}`;
  if (to) return <Link to={to} className={cls}>{body}</Link>;
  if (onClick) return <button type="button" className={cls} onClick={onClick}>{body}</button>;
  return <div className={cls}>{body}</div>;
}
