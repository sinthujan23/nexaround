import { useState } from 'react';
import { useApi, apiPost } from '../api';
import { MonitorIcon, SmartphoneIcon, LogOutIcon } from '../components/Icons';
import { HeroBanner, HeroCount, Card, Badge, Loading, EmptyState, PageError } from '../components/Kit';
import {
  ACTOR_LABELS, ACTOR_TONES, REVOKE_REASONS, deviceLabel, formatWhen, timeAgo,
} from '../audit';

const PAGE_SIZE = 25;

const STATUS_TONES = { active: 'green', ended: 'ghost', revoked: 'red' };
const STATUS_LABELS = { active: 'Active', ended: 'Expired', revoked: 'Signed out' };

export default function Sessions() {
  const [page, setPage] = useState(1);
  const [state, setState] = useState('active');
  const [actorType, setActorType] = useState('');
  const [busy, setBusy] = useState(null);
  const [message, setMessage] = useState('');

  const params = new URLSearchParams({ page: String(page), page_size: String(PAGE_SIZE), state });
  if (actorType) params.set('actor_type', actorType);
  const { data, loading, error, refetch } = useApi(`/admin/sessions?${params.toString()}`);

  const items = data?.items || [];
  const total = data?.total || 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const revoke = async (s) => {
    const who = `${s.actor_label} on ${deviceLabel(s.browser, s.os)}`;
    if (!window.confirm(`Sign ${who} out? They will need to sign in again.`)) return;
    setBusy(s.id);
    setMessage('');
    try {
      await apiPost(`/admin/sessions/${s.id}/revoke`);
      refetch();
    } catch (err) {
      setMessage(err.message);
    } finally {
      setBusy(null);
    }
  };

  if (error && !data) {
    return <PageError error={error} onRetry={refetch} title="Unable to Load Devices">Failed to load devices: {error}</PageError>;
  }

  return (
    <div>
      <HeroBanner title="Devices & Sessions">
        {state === 'active'
          ? <><HeroCount>{total}</HeroCount> device{total === 1 ? ' is' : 's are'} signed in to the admin panel and partner portal.</>
          : <>Every sign-in on record: <HeroCount>{total}</HeroCount>.</>}
        {' '}Signing a device out takes effect on its next request.
      </HeroBanner>

      <Card title="Signed-in devices">
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '10px', alignItems: 'center', marginBottom: '16px' }}>
          <div className="segmented-tabs" role="tablist">
            {[['active', 'Active now'], ['all', 'All history']].map(([key, label]) => (
              <button
                key={key} type="button" role="tab" aria-selected={state === key}
                className={`segmented-tab ${state === key ? 'active' : ''}`}
                onClick={() => { setState(key); setPage(1); }}
              >
                <span>{label}</span>
              </button>
            ))}
          </div>
          <select
            className={`aud-select ${actorType ? 'is-set' : ''}`} value={actorType}
            onChange={(e) => { setActorType(e.target.value); setPage(1); }} aria-label="Who"
          >
            <option value="">Admin and partners</option>
            <option value="admin">Admin only</option>
            <option value="vendor">Partners only</option>
          </select>
        </div>

        {message && <div style={{ color: 'var(--danger)', fontSize: '13px', marginBottom: '12px' }}>{message}</div>}

        {loading && !data ? (
          <Loading>Loading devices...</Loading>
        ) : items.length === 0 ? (
          <EmptyState icon={<MonitorIcon size={28} />} title="No devices">
            {state === 'active' ? 'Nobody is signed in right now.' : 'No sign-ins have been recorded yet.'}
          </EmptyState>
        ) : (
          <div className="table-wrap" style={{ opacity: loading ? 0.6 : 1 }}>
            <table>
              <thead>
                <tr>
                  <th>Who</th>
                  <th>Device</th>
                  <th>IP address</th>
                  <th>Signed in (SLST)</th>
                  <th>Last active</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {items.map((s) => {
                  const Icon = s.device_type === 'mobile' || s.device_type === 'tablet' ? SmartphoneIcon : MonitorIcon;
                  return (
                    <tr key={s.id}>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                          <Badge tone={ACTOR_TONES[s.actor_type]}>{ACTOR_LABELS[s.actor_type]}</Badge>
                          <span style={{ fontWeight: 600 }}>{s.actor_label}</span>
                        </div>
                        {s.vendor_name && <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '2px' }}>{s.vendor_name}</div>}
                      </td>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                          <Icon size={16} style={{ color: 'var(--text-secondary)', flexShrink: 0 }} />
                          <span>{deviceLabel(s.browser, s.os)}</span>
                          {s.is_current && <Badge tone="blue">This device</Badge>}
                        </div>
                      </td>
                      <td>
                        <div>{s.last_ip || s.ip || '—'}</div>
                        {s.ip && s.last_ip && s.ip !== s.last_ip && (
                          <div style={{ fontSize: '12px', color: 'var(--warning)', marginTop: '2px' }} title="The IP address changed during this session">
                            signed in from {s.ip}
                          </div>
                        )}
                      </td>
                      <td style={{ whiteSpace: 'nowrap', color: 'var(--text-secondary)' }}>{formatWhen(s.created_at)}</td>
                      <td style={{ whiteSpace: 'nowrap' }} title={formatWhen(s.last_seen_at)}>{timeAgo(s.last_seen_at)}</td>
                      <td>
                        <Badge tone={STATUS_TONES[s.status]}>{STATUS_LABELS[s.status]}</Badge>
                        {s.status === 'revoked' && (
                          <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '2px' }}>
                            {REVOKE_REASONS[s.revoked_reason] || 'Signed out'}{s.revoked_by && s.revoked_reason === 'admin' ? ` (${s.revoked_by})` : ''}
                          </div>
                        )}
                      </td>
                      <td>
                        {s.status === 'active' && !s.is_current && (
                          <button
                            type="button" className="btn btn-ghost btn-sm" disabled={busy === s.id}
                            style={{ color: 'var(--danger)' }} onClick={() => revoke(s)}
                          >
                            <LogOutIcon size={14} /> Sign out
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        {totalPages > 1 && (
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '20px' }}>
            <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>Page {page} of {totalPages}</span>
            <div style={{ display: 'flex', gap: '10px' }}>
              <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: '12px' }} onClick={() => setPage((p) => Math.max(1, p - 1))} disabled={page === 1}>Previous</button>
              <button className="btn btn-ghost" style={{ padding: '6px 12px', fontSize: '12px' }} onClick={() => setPage((p) => Math.min(totalPages, p + 1))} disabled={page === totalPages}>Next</button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}
