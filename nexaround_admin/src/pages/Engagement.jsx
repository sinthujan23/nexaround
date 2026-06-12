import React, { useState, useEffect } from 'react';
import { apiGet, apiPost } from '../api';
import { UsersIcon, TimerIcon, CompassIcon, MegaphoneIcon, CheckIcon, CrossIcon, TrendingUpIcon } from '../components/Icons';

const STATUS_LABEL = { sent: 'Received', failed: 'Failed', no_token: 'No device', pending: 'Pending' };
const STATUS_STYLE = {
  sent: { background: '#e6f7ee', color: '#0a7d3c' },
  failed: { background: '#fdecea', color: '#c0392b' },
  no_token: { background: '#f0f0f3', color: '#777' },
  pending: { background: '#fff7e6', color: '#b8860b' },
};

export default function Engagement() {
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [targetPlan, setTargetPlan] = useState('all');
  const [sending, setSending] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  // Real metrics + history from the backend.
  const [metrics, setMetrics] = useState({
    daily_active_users: 0,
    avg_session_length: '—',
    places_visited_count: 0,
  });
  const [recentBroadcasts, setRecentBroadcasts] = useState([]);

  const loadStats = () => {
    apiGet('/admin/engagement/stats').then(setMetrics).catch(() => {});
  };

  const loadHistory = () => {
    apiGet('/admin/engagement/broadcasts')
      .then((list) => setRecentBroadcasts((list || []).map((b) => ({
        id: b.id,
        title: b.title,
        target: b.target_audience === 'all' ? 'All Explorers' : b.target_audience,
        date: new Date(b.created_at).toLocaleString(),
        sent: b.devices_sent,
        failed: b.devices_failed,
      }))))
      .catch(() => {});
  };

  useEffect(() => {
    loadStats();
    loadHistory();
  }, []);

  const handleBroadcast = async (e) => {
    e.preventDefault();
    setSending(true);
    setSuccessMsg('');
    setErrorMsg('');
    try {
      const res = await apiPost('/admin/engagement/announcements', {
        title,
        message,
        target_plan: targetPlan,
      });
      setSuccessMsg(res?.message || 'Broadcast is being delivered to your audience.');
      setTitle('');
      setMessage('');
      // Delivery runs in a background task; give it a moment, then refresh
      // history so the real send (with delivery counts) shows up.
      setTimeout(loadHistory, 2000);
      setTimeout(() => setSuccessMsg(''), 6000);
    } catch (err) {
      setErrorMsg(err.message || 'Failed to send broadcast. Please try again.');
    } finally {
      setSending(false);
    }
  };

  // --- Broadcast detail modal: per-recipient delivery breakdown + search ---
  const [detailBc, setDetailBc] = useState(null);       // { id, title }
  const [detail, setDetail] = useState(null);           // { total_recipients, summary, recipients }
  const [detailSearch, setDetailSearch] = useState('');
  const [detailStatus, setDetailStatus] = useState(''); // '' | sent | failed | no_token | pending
  const [detailLoading, setDetailLoading] = useState(false);

  const openDetail = (b) => {
    setDetailBc(b);
    setDetailSearch('');
    setDetailStatus('');
    setDetail(null);
  };
  const closeDetail = () => { setDetailBc(null); setDetail(null); };

  // Fetch recipients whenever the open broadcast / search / status changes
  // (debounced so typing in the search box doesn't spam the API).
  useEffect(() => {
    if (!detailBc) return;
    setDetailLoading(true);
    const params = new URLSearchParams();
    if (detailSearch.trim()) params.set('search', detailSearch.trim());
    if (detailStatus) params.set('status', detailStatus);
    const qs = params.toString() ? `?${params.toString()}` : '';
    const handle = setTimeout(() => {
      apiGet(`/admin/engagement/broadcasts/${detailBc.id}/recipients${qs}`)
        .then(setDetail)
        .catch(() => setDetail({ total_recipients: 0, summary: {}, recipients: [] }))
        .finally(() => setDetailLoading(false));
    }, 250);
    return () => clearTimeout(handle);
  }, [detailBc, detailSearch, detailStatus]);

  return (
    <div style={{ paddingBottom: '40px' }}>
      <div className="card-header" style={{ marginBottom: '24px' }}>
        <div>
          <div className="card-title">Engagement & Reach</div>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)', marginTop: '4px' }}>
            Monitor user activity and broadcast announcements via push notifications.
          </div>
        </div>
      </div>

      {/* Stats */}
      <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)', marginBottom: '32px' }}>
        <div className="stat-card">
          <div className="stat-icon">
            <UsersIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{metrics.daily_active_users.toLocaleString()}</div>
          <div className="stat-label">Daily Active Users</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> 5.1% vs last week
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <TimerIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{metrics.avg_session_length}</div>
          <div className="stat-label">Avg Session Length</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> 12s vs last week
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-icon">
            <CompassIcon size={24} style={{ color: 'var(--accent)' }} />
          </div>
          <div className="stat-value">{metrics.places_visited_count.toLocaleString()}</div>
          <div className="stat-label">Places Visited</div>
          <span className="stat-change up" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
            <TrendingUpIcon size={12} /> 8.2% vs last month
          </span>
        </div>
      </div>

      {/* Two Column Layout */}
      <div className="approvals-split">
        {/* Left: Broadcast Form */}
        <div className="card" style={{ margin: 0 }}>
          <div className="card-header">
            <div className="card-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <MegaphoneIcon size={18} style={{ color: 'var(--accent)' }} /> New Broadcast
            </div>
          </div>

          {successMsg && (
            <div className="badge badge-green" style={{ display: 'block', padding: '14px 18px', borderRadius: '12px', marginBottom: '24px', fontSize: '13.5px', background: 'var(--accent)', color: '#fff', boxShadow: '0 8px 20px rgba(0, 122, 124, 0.2)' }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontWeight: 700 }}>
                <CheckIcon size={18} /> {successMsg}
              </div>
            </div>
          )}

          {errorMsg && (
            <div className="badge" style={{ display: 'block', padding: '14px 18px', borderRadius: '12px', marginBottom: '24px', fontSize: '13.5px', background: '#c0392b', color: '#fff' }}>
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontWeight: 700 }}>
                <CrossIcon size={18} /> {errorMsg}
              </div>
            </div>
          )}

          <form onSubmit={handleBroadcast}>
            <div className="form-group">
              <label className="form-label">Target Audience</label>
              <select
                className="form-select"
                value={targetPlan}
                onChange={(e) => setTargetPlan(e.target.value)}
                style={{ background: 'var(--bg-dark)' }}
              >
                <option value="all">All Explorers (Free & Pro)</option>
                <option value="Pro Explorer">Pro Explorers Only</option>
                <option value="Annual Pass">Annual Pass Holders Only</option>
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">Notification Title</label>
              <input
                type="text"
                className="form-input"
                placeholder="e.g. 50% Off Annual Passes!"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                required
              />
            </div>

            <div className="form-group">
              <label className="form-label">Notification Body</label>
              <textarea
                className="form-textarea"
                placeholder="Enter push notification message here..."
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                required
                style={{ minHeight: '140px' }}
              />
            </div>

            <button
              type="submit"
              className="btn btn-primary"
              style={{ width: '100%', marginTop: '16px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px', padding: '14px', fontSize: '14.5px' }}
              disabled={sending}
            >
              {sending ? (
                <>Broadcasting... 📡</>
              ) : (
                <>
                  <MegaphoneIcon size={18} /> Send Push Notification
                </>
              )}
            </button>
          </form>
        </div>

        {/* Right: History */}
        <div className="card" style={{ margin: 0, background: 'var(--bg-dark)' }}>
          <div className="card-header">
            <div className="card-title">Broadcast History</div>
          </div>
          
          <div className="modern-list" style={{ marginTop: '8px' }}>
            {recentBroadcasts.length === 0 && (
              <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: '13px' }}>
                No broadcasts sent yet.
              </div>
            )}
            {recentBroadcasts.map((b) => (
              <div
                className="modern-list-item"
                key={b.id}
                onClick={() => openDetail(b)}
                title="View delivery details"
                style={{ background: 'var(--bg-card)', padding: '16px', alignItems: 'flex-start', cursor: 'pointer' }}
              >
                <div className="list-item-main">
                  <div className="list-item-icon" style={{ background: 'var(--accent-light)', color: 'var(--accent)', borderRadius: '50%', width: '32px', height: '32px' }}>
                    <MegaphoneIcon size={14} />
                  </div>
                  <div className="list-item-content">
                    <div className="list-item-title" style={{ fontSize: '13.5px' }}>{b.title}</div>
                    <div className="list-item-meta" style={{ marginTop: '2px' }}>
                      <span className="badge badge-blue" style={{ fontSize: '9px', padding: '2px 6px' }}>{b.target}</span>
                      <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>{b.date}</span>
                      {typeof b.sent === 'number' && (
                        <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>· {b.sent} sent{b.failed ? `, ${b.failed} failed` : ''}</span>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Broadcast detail popup: who received it, who failed, with user search */}
      {detailBc && (
        <div
          onClick={closeDetail}
          style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000, padding: '20px' }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="card"
            style={{ margin: 0, width: '100%', maxWidth: '620px', maxHeight: '85vh', display: 'flex', flexDirection: 'column' }}
          >
            <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px' }}>
              <div style={{ minWidth: 0 }}>
                <div className="card-title" style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{detailBc.title}</div>
                <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '4px' }}>
                  Delivery breakdown · {detail?.total_recipients ?? '…'} recipients
                </div>
              </div>
              <button onClick={closeDetail} className="btn" style={{ background: 'transparent', border: 'none', padding: '4px', cursor: 'pointer', color: 'var(--text-secondary)' }}>
                <CrossIcon size={18} />
              </button>
            </div>

            {/* Summary chips double as status filters */}
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '14px' }}>
              {[
                { key: '', label: 'All', count: detail?.total_recipients },
                { key: 'sent', label: 'Received', count: detail?.summary?.sent },
                { key: 'failed', label: 'Failed', count: detail?.summary?.failed },
                { key: 'no_token', label: 'No device', count: detail?.summary?.no_token },
                { key: 'pending', label: 'Pending', count: detail?.summary?.pending },
              ].map((s) => (
                <button
                  key={s.key || 'all'}
                  onClick={() => setDetailStatus(s.key)}
                  style={{
                    cursor: 'pointer', padding: '7px 12px', borderRadius: '10px', fontSize: '12px',
                    border: detailStatus === s.key ? '2px solid var(--accent)' : '1px solid rgba(0,0,0,0.1)',
                    background: detailStatus === s.key ? 'var(--accent-light)' : 'var(--bg-card)',
                    color: 'var(--text-primary)', fontWeight: 600,
                  }}
                >
                  {s.label} <strong>{s.count ?? 0}</strong>
                </button>
              ))}
            </div>

            <input
              type="text"
              className="form-input"
              placeholder="Search recipients by name or email…"
              value={detailSearch}
              onChange={(e) => setDetailSearch(e.target.value)}
              style={{ marginBottom: '12px' }}
            />

            <div style={{ overflowY: 'auto', flex: 1, border: '1px solid rgba(0,0,0,0.06)', borderRadius: '10px' }}>
              {detailLoading && (
                <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: '13px' }}>Loading…</div>
              )}
              {!detailLoading && detail && detail.recipients.length === 0 && (
                <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: '13px' }}>No recipients match.</div>
              )}
              {!detailLoading && detail && detail.recipients.map((r) => (
                <div key={r.user_id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '11px 14px', borderBottom: '1px solid rgba(0,0,0,0.05)' }}>
                  <div style={{ minWidth: 0 }}>
                    <div style={{ fontSize: '13.5px', fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.name}</div>
                    <div style={{ fontSize: '11.5px', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{r.email}</div>
                  </div>
                  <span style={{ ...(STATUS_STYLE[r.push_status] || STATUS_STYLE.pending), fontSize: '11px', fontWeight: 700, padding: '4px 10px', borderRadius: '20px', whiteSpace: 'nowrap', marginLeft: '12px' }}>
                    {STATUS_LABEL[r.push_status] || r.push_status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
