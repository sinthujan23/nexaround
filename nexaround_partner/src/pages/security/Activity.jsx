import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { apiGet } from '../../api';
import { ShieldIcon, AlertTriangleIcon, EditIcon } from '../../components/Icons';
import { EmptyState, ErrorBanner, ListRow, Loader, Pagination, Tabs } from '../../components/Lists';
import { clock, deviceLabel, groupByDay } from './format';

const PAGE_SIZE = 20;

const TYPES = [
  { value: '', label: 'Everything' },
  { value: 'auth', label: 'Sign-ins' },
  { value: 'change', label: 'Changes' },
];

/** Sign-ins and changes on the account, newest first. The filter and page are in the URL. */
export default function Activity() {
  const [params, setParams] = useSearchParams();
  const type = params.get('type') || '';
  const page = Math.max(1, Number(params.get('page')) || 1);

  const [events, setEvents] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let active = true;
    const query = new URLSearchParams({ page: String(page), page_size: String(PAGE_SIZE) });
    if (type) query.set('category', type);
    apiGet(`/partner/audit?${query}`)
      .then((r) => { if (active) { setEvents(r); setError(''); } })
      .catch((err) => { if (active) setError(err.message || 'Could not load the activity log.'); });
    return () => { active = false; };
  }, [type, page]);

  const setQuery = (changes) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(changes)) {
      if (v) next.set(k, v); else next.delete(k);
    }
    setParams(next);
  };

  const totalPages = Math.max(1, Math.ceil((events?.total || 0) / PAGE_SIZE));

  return (
    <section className="card sec-card">
      <div className="sec-head">
        <div>
          <h2 className="sec-title">Account activity</h2>
          <p className="sec-sub">Sign-ins and changes on your business account. Records can't be edited or removed.</p>
        </div>
        <Tabs items={TYPES} value={type} onChange={(v) => setQuery({ type: v, page: '' })} />
      </div>
      <div className="sec-body">
        <ErrorBanner>{error}</ErrorBanner>
        {events === null && !error && <Loader />}
        {events && events.items.length === 0 && (
          <EmptyState icon={ShieldIcon} title="Nothing recorded yet" />
        )}
        {events && groupByDay(events.items).map((g) => (
          <div key={g.key}>
            <div className="sec-day">{g.label}</div>
            {g.items.map((e) => {
              const Icon = !e.success ? AlertTriangleIcon : e.category === 'change' ? EditIcon : ShieldIcon;
              return (
                <ListRow
                  key={e.id}
                  variant="sec"
                  lead={<span className={`sec-tile ${e.success ? '' : 'failed'}`}><Icon size={17} /></span>}
                  title={e.summary}
                  subs={`${e.is_you ? 'You' : (e.actor_label || 'Someone')} · ${deviceLabel(e.browser, e.os)} · ${e.ip || 'Unknown IP'}`}
                  side={(
                    <>
                      {!e.success && <span className="badge badge-red">Failed</span>}
                      <span className="sec-time">{clock(e.occurred_at)}</span>
                    </>
                  )}
                />
              );
            })}
          </div>
        ))}
      </div>
      <Pagination page={page} totalPages={totalPages} onPage={(p) => setQuery({ page: p > 1 ? String(p) : '' })} />
    </section>
  );
}
