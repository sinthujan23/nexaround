import { Fragment, useEffect, useState } from 'react';
import { useApi } from '../api';
import {
  ShieldIcon, AlertTriangleIcon, EditIcon, EyeIcon, MonitorIcon, SearchIcon, ChevronDownIcon,
} from '../components/Icons';
import { HeroBanner, StatCard, Card, SearchBar, Loading, EmptyState, PageError } from '../components/Kit';
import {
  ACTOR_LABELS, CATEGORY_LABELS, deviceLabel, formatClock, formatDay, formatWhen,
} from '../audit';

const PAGE_SIZE = 25;

const TYPE_TABS = [
  ['', 'All activity'],
  ['auth', 'Sign-ins & security'],
  ['change', 'Changes'],
  ['access', 'Sensitive views'],
];

const CATEGORY_ICONS = { auth: ShieldIcon, change: EditIcon, access: EyeIcon };

function EventDetails({ e }) {
  const rows = [
    ['Time', formatWhen(e.occurred_at)],
    ['Person', `${e.actor_label || '—'}${e.vendor_name ? ` · ${e.vendor_name}` : ''}`],
    ['Device', deviceLabel(e.browser, e.os)],
    ['IP address', e.ip || '—'],
    e.method && ['Request', `${e.method} ${e.path || e.route || ''}`],
    e.status_code != null && ['Status code', String(e.status_code)],
    e.target_id && ['Target', e.target_id],
    e.detail?.reason && ['Reason', e.detail.reason],
    e.detail?.fields && ['Fields changed', e.detail.fields.join(', ')],
    e.session_id && ['Session', e.session_id],
  ].filter(Boolean);
  return (
    <dl className="aud-detail">
      {rows.map(([k, v]) => (
        <div key={k}><dt>{k}</dt><dd>{v}</dd></div>
      ))}
    </dl>
  );
}

export default function AuditTrail() {
  const [page, setPage] = useState(1);
  const [actorType, setActorType] = useState('');
  const [category, setCategory] = useState('');
  const [outcome, setOutcome] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [search, setSearch] = useState('');
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(null);

  useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const params = new URLSearchParams({ page: String(page), page_size: String(PAGE_SIZE) });
  if (actorType) params.set('actor_type', actorType);
  if (category) params.set('category', category);
  if (outcome) params.set('outcome', outcome);
  if (dateFrom) params.set('date_from', dateFrom);
  if (dateTo) params.set('date_to', dateTo);
  if (q) params.set('q', q);

  const { data, loading, error, refetch } = useApi(`/admin/audit?${params.toString()}`);

  const narrowed = Boolean(actorType || outcome || dateFrom || dateTo || q);
  const filtered = narrowed || Boolean(category);
  const items = data?.items || [];
  const total = data?.total || 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const stats = data?.stats;

  const pick = (setter) => (value) => { setter(value); setPage(1); setOpen(null); };
  const clear = () => {
    setActorType(''); setOutcome(''); setDateFrom(''); setDateTo('');
    setSearch(''); setPage(1); setOpen(null);
  };

  if (error && !data) {
    return <PageError error={error} onRetry={refetch} title="Unable to Load the Audit Trail">Failed to load the audit trail: {error}</PageError>;
  }

  return (
    <div>
      <HeroBanner title="Audit Trail">
        A permanent record of who signed in, what they changed and which sensitive data they viewed.
      </HeroBanner>

      {stats && (
        <div className="stats-grid">
          <StatCard icon={ShieldIcon} value={stats.events_24h.toLocaleString()} label="Events in the last 24 h" />
          <StatCard
            icon={AlertTriangleIcon}
            iconColor={stats.failed_sign_ins_24h > 0 ? 'var(--danger)' : 'var(--accent)'}
            value={stats.failed_sign_ins_24h.toLocaleString()} label="Failed sign-ins (24 h)"
          />
          <StatCard icon={EditIcon} value={stats.changes_24h.toLocaleString()} label="Changes made (24 h)" />
          <StatCard icon={MonitorIcon} value={stats.active_sessions.toLocaleString()} label="Devices signed in now" />
        </div>
      )}

      <Card
        title="Activity"
        action={<span className="aud-count">{total.toLocaleString()} {total === 1 ? 'event' : 'events'} · read-only</span>}
      >
        <div className="aud-toolbar">
          <div className="segmented-tabs" role="tablist">
            {TYPE_TABS.map(([key, label]) => (
              <button
                key={key || 'all'} type="button" role="tab" aria-selected={category === key}
                className={`segmented-tab ${category === key ? 'active' : ''}`}
                onClick={() => pick(setCategory)(key)}
              >
                <span>{label}</span>
              </button>
            ))}
          </div>
          <SearchBar value={search} onChange={setSearch} placeholder="Search person, IP or action…" style={{ width: '280px', maxWidth: '100%' }} />
        </div>

        <div className="aud-filters">
          <span className="aud-filters-label">Filter</span>
          <select
            className={`aud-select ${actorType ? 'is-set' : ''}`} value={actorType}
            onChange={(e) => pick(setActorType)(e.target.value)} aria-label="Person"
          >
            <option value="">Everyone</option>
            <option value="admin">Admin</option>
            <option value="vendor">Partners</option>
            <option value="creator">Content creators</option>
            <option value="anonymous">Unknown (failed sign-ins)</option>
          </select>
          <select
            className={`aud-select ${outcome ? 'is-set' : ''}`} value={outcome}
            onChange={(e) => pick(setOutcome)(e.target.value)} aria-label="Result"
          >
            <option value="">Any result</option>
            <option value="success">Succeeded</option>
            <option value="failed">Failed or refused</option>
          </select>
          <span className={`aud-daterange ${dateFrom || dateTo ? 'is-set' : ''}`}>
            <input type="date" value={dateFrom} max={dateTo || undefined} onChange={(e) => pick(setDateFrom)(e.target.value)} aria-label="From date" />
            →
            <input type="date" value={dateTo} min={dateFrom || undefined} onChange={(e) => pick(setDateTo)(e.target.value)} aria-label="To date" />
          </span>
          {narrowed && <button type="button" className="aud-clear" onClick={clear}>Clear filters</button>}
        </div>

        {loading && !data ? (
          <Loading>Loading the audit trail…</Loading>
        ) : items.length === 0 ? (
          <EmptyState icon={<SearchIcon size={28} />} title="No events found">
            {filtered ? 'Nothing matches these filters.' : 'Nothing has been recorded yet.'}
          </EmptyState>
        ) : (
          <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1, marginTop: '8px' }}>
            <table className="aud-table">
              <thead>
                <tr>
                  <th>When</th>
                  <th>Person</th>
                  <th>Event</th>
                  <th>Device</th>
                  <th>Result</th>
                  <th aria-label="Details" />
                </tr>
              </thead>
              <tbody>
                {items.map((e) => {
                  const Icon = e.success ? (CATEGORY_ICONS[e.category] || ShieldIcon) : AlertTriangleIcon;
                  const isOpen = open === e.id;
                  return (
                    <Fragment key={e.id}>
                      <tr className={`aud-row ${isOpen ? 'is-open' : ''}`} onClick={() => setOpen(isOpen ? null : e.id)}>
                        <td className="aud-time"><strong>{formatDay(e.occurred_at)}</strong><span>{formatClock(e.occurred_at)}</span></td>
                        <td>
                          <div className="aud-person">
                            <strong>{e.actor_label || '—'}</strong>
                            <span className={`aud-role ${e.actor_type}`}>
                              {ACTOR_LABELS[e.actor_type] || e.actor_type}{e.vendor_name ? ` · ${e.vendor_name}` : ''}
                            </span>
                          </div>
                        </td>
                        <td>
                          <div className="aud-event">
                            <span className={`aud-ico ${e.success ? e.category : 'failed'}`}><Icon size={16} /></span>
                            <div className="aud-event-text">
                              <div>{e.summary}</div>
                              <small>{CATEGORY_LABELS[e.category] || e.category}</small>
                            </div>
                          </div>
                        </td>
                        <td className="aud-device">{deviceLabel(e.browser, e.os)}<small>{e.ip || '—'}</small></td>
                        <td><span className={`aud-status ${e.success ? '' : 'failed'}`}>{e.success ? 'Success' : 'Failed'}</span></td>
                        <td><span className="aud-chevron"><ChevronDownIcon size={16} /></span></td>
                      </tr>
                      {isOpen && (
                        <tr className="aud-detail-row"><td colSpan="6"><EventDetails e={e} /></td></tr>
                      )}
                    </Fragment>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {totalPages > 1 && (
          <div className="aud-pager">
            <span>Page {page} of {totalPages}</span>
            <div>
              <button className="btn btn-ghost btn-sm" onClick={() => { setPage((p) => Math.max(1, p - 1)); setOpen(null); }} disabled={page === 1}>Previous</button>
              <button className="btn btn-ghost btn-sm" onClick={() => { setPage((p) => Math.min(totalPages, p + 1)); setOpen(null); }} disabled={page === totalPages}>Next</button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
