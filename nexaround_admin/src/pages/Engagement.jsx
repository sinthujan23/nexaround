import { useState, useEffect, useMemo } from 'react';
import { apiGet, apiPost } from '../api';
import {
  UsersIcon,
  MegaphoneIcon,
  CheckIcon,
  CrossIcon,
  TrendingUpIcon,
  SmartphoneIcon,
  BellIcon,
  SendIcon,
  SearchIcon,
  RefreshIcon,
  CheckCircleIcon,
} from '../components/Icons';
import { Card, Badge } from '../components/Kit';

const STATUS_LABEL = { sent: 'Received', failed: 'Failed', no_token: 'No device', pending: 'Pending' };
const STATUS_STYLE = {
  sent: { background: '#e6f7ee', color: '#0a7d3c' },
  failed: { background: '#fdecea', color: '#c0392b' },
  no_token: { background: '#f0f0f3', color: '#777' },
  pending: { background: '#fff7e6', color: '#b8860b' },
};

const QUICK_TEMPLATES = [
  {
    label: '✨ Weekend Discoveries',
    title: 'Weekend Spots You’ll Love!',
    message: 'Explore trending cafes, scenic viewpoints, and popular places around you this weekend.',
  },
  {
    label: '📍 New Places Added',
    title: 'Fresh Places Just Verified!',
    message: 'We added newly verified places to the map. Open nexARound to find your next favorite spot!',
  },
  {
    label: '📣 Community Update',
    title: 'nexARound App Update',
    message: 'Enjoy smoother searches, refreshed maps, and faster recommendations in our latest release.',
  },
];

export default function Engagement() {
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');
  const [errorMsg, setErrorMsg] = useState('');

  // Real broadcasts history & registered users count
  const [recentBroadcasts, setRecentBroadcasts] = useState([]);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [historySearch, setHistorySearch] = useState('');
  const [totalUsers, setTotalUsers] = useState(null);

  const loadHistory = () => {
    setLoadingHistory(true);
    apiGet('/admin/engagement/broadcasts')
      .then((list) => {
        setRecentBroadcasts(
          (list || []).map((b) => ({
            id: b.id,
            title: b.title,
            body: b.body,
            target: b.target_audience === 'all' ? 'All Explorers' : b.target_audience,
            date: new Date(b.created_at).toLocaleString([], {
              month: 'short',
              day: 'numeric',
              hour: '2-digit',
              minute: '2-digit',
            }),
            rawDate: b.created_at,
            sent: b.devices_sent,
            failed: b.devices_failed,
            recipients_count: b.recipients_count,
            status: b.status,
          }))
        );
      })
      .catch(() => {})
      .finally(() => setLoadingHistory(false));
  };

  useEffect(() => {
    loadHistory();
    apiGet('/admin/users?page_size=1')
      .then((res) => {
        if (typeof res?.total === 'number') setTotalUsers(res.total);
      })
      .catch(() => {});
  }, []);

  // Compute 100% real delivery metrics from active records
  const totalCampaigns = recentBroadcasts.length;
  const totalDelivered = recentBroadcasts.reduce((sum, b) => sum + (b.sent || 0), 0);
  const totalFailed = recentBroadcasts.reduce((sum, b) => sum + (b.failed || 0), 0);
  const totalAttempted = totalDelivered + totalFailed;
  const deliveryRate =
    totalAttempted > 0 ? `${Math.round((totalDelivered / totalAttempted) * 100)}%` : '100%';

  const handleBroadcast = async (e) => {
    e.preventDefault();
    if (!title.trim() || !message.trim()) return;
    setSending(true);
    setSuccessMsg('');
    setErrorMsg('');
    try {
      const res = await apiPost('/admin/engagement/announcements', {
        title: title.trim(),
        message: message.trim(),
        target_plan: 'all', // Reaches all regular registered mobile app users
      });
      setSuccessMsg(res?.message || 'Broadcast is being delivered to all user devices.');
      setTitle('');
      setMessage('');
      // Refresh history after background task processes
      setTimeout(loadHistory, 2000);
      setTimeout(() => setSuccessMsg(''), 6000);
    } catch (err) {
      setErrorMsg(err.message || 'Failed to send broadcast. Please try again.');
    } finally {
      setSending(false);
    }
  };

  const applyTemplate = (tpl) => {
    setTitle(tpl.title);
    setMessage(tpl.message);
  };

  // Filtered broadcast history
  const filteredHistory = useMemo(() => {
    if (!historySearch.trim()) return recentBroadcasts;
    const q = historySearch.toLowerCase();
    return recentBroadcasts.filter(
      (b) =>
        b.title?.toLowerCase().includes(q) ||
        b.body?.toLowerCase().includes(q) ||
        b.target?.toLowerCase().includes(q)
    );
  }, [recentBroadcasts, historySearch]);

  // --- Broadcast detail modal: per-recipient delivery breakdown + search ---
  const [detailBc, setDetailBc] = useState(null);
  const [detail, setDetail] = useState(null);
  const [detailSearch, setDetailSearch] = useState('');
  const [detailStatus, setDetailStatus] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);

  const openDetail = (b) => {
    setDetailBc(b);
    setDetailSearch('');
    setDetailStatus('');
    setDetail(null);
    setDetailLoading(true);
  };
  const closeDetail = () => {
    setDetailBc(null);
    setDetail(null);
  };
  const changeDetailSearch = (value) => {
    setDetailSearch(value);
    setDetailLoading(true);
  };
  const changeDetailStatus = (status) => {
    if (status === detailStatus) return;
    setDetailStatus(status);
    setDetailLoading(true);
  };

  useEffect(() => {
    if (!detailBc) return;
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
      {/* Top Header */}
      <div className="engagement-header">
        <div>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
            Compose real-time push announcements & in-app alerts sent directly to user mobile devices.
          </div>
        </div>
        <div className="engine-status-pill">
          <span className="pulse-live" />
          <span>FCM Push Engine Active</span>
        </div>
      </div>

      {/* Real Broadcast Metrics (Replaced dummy cards) */}
      <div className="stats-grid" style={{ gridTemplateColumns: 'repeat(4, 1fr)', marginBottom: '24px' }}>
        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-label">Total Campaigns</span>
            <div className="stat-icon" style={{ background: 'var(--accent-light)', color: 'var(--accent)' }}>
              <MegaphoneIcon size={18} />
            </div>
          </div>
          <div className="stat-value">{totalCampaigns}</div>
          <div className="stat-sub">Announcements broadcasted</div>
        </div>

        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-label">Delivered Alerts</span>
            <div className="stat-icon" style={{ background: '#e6f7ee', color: '#0a7d3c' }}>
              <CheckCircleIcon size={18} />
            </div>
          </div>
          <div className="stat-value">{totalDelivered.toLocaleString()}</div>
          <div className="stat-sub">Successfully received on devices</div>
        </div>

        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-label">Delivery Rate</span>
            <div className="stat-icon" style={{ background: '#eef2ff', color: '#4f46e5' }}>
              <TrendingUpIcon size={18} />
            </div>
          </div>
          <div className="stat-value">{deliveryRate}</div>
          <div className="stat-sub">{totalFailed > 0 ? `${totalFailed} failed devices` : 'Zero delivery failures'}</div>
        </div>

        <div className="stat-card">
          <div className="stat-card-header">
            <span className="stat-label">Target Audience</span>
            <div className="stat-icon" style={{ background: 'rgba(0,122,124,0.1)', color: 'var(--accent)' }}>
              <UsersIcon size={18} />
            </div>
          </div>
          <div className="stat-value">{totalUsers !== null ? `${totalUsers.toLocaleString()} Users` : 'All Explorers'}</div>
          <div className="stat-sub">All active registered devices</div>
        </div>
      </div>

      {/* Studio Grid: Composer & Preview on Left, History on Right */}
      <div className="studio-grid">
        {/* Left: Push Notification Composer */}
        <Card style={{ margin: 0 }}>
          <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div className="card-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <MegaphoneIcon size={18} style={{ color: 'var(--accent)' }} /> Broadcast Composer
            </div>
            <Badge tone="teal" style={{ fontSize: '11px', padding: '3px 8px' }}>
              Push & In-App Alert
            </Badge>
          </div>

          {/* Quick preset templates */}
          <div style={{ marginBottom: '8px' }}>
            <label className="form-label" style={{ fontSize: '11.5px', textTransform: 'uppercase', letterSpacing: '0.04em' }}>
              Quick Templates
            </label>
            <div className="template-chips-row">
              {QUICK_TEMPLATES.map((t, i) => (
                <button
                  key={i}
                  type="button"
                  className="template-chip"
                  onClick={() => applyTemplate(t)}
                  title="Click to populate message"
                >
                  {t.label}
                </button>
              ))}
            </div>
          </div>

          {successMsg && (
            <div
              className="badge badge-green"
              style={{
                display: 'block',
                padding: '12px 16px',
                borderRadius: '12px',
                marginBottom: '20px',
                fontSize: '13px',
                background: 'var(--accent)',
                color: '#fff',
                boxShadow: '0 6px 18px rgba(0, 122, 124, 0.2)',
              }}
            >
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontWeight: 600 }}>
                <CheckIcon size={16} /> {successMsg}
              </div>
            </div>
          )}

          {errorMsg && (
            <div
              className="badge"
              style={{
                display: 'block',
                padding: '12px 16px',
                borderRadius: '12px',
                marginBottom: '20px',
                fontSize: '13px',
                background: '#c0392b',
                color: '#fff',
              }}
            >
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', fontWeight: 600 }}>
                <CrossIcon size={16} /> {errorMsg}
              </div>
            </div>
          )}

          <form onSubmit={handleBroadcast}>
            {/* Target Audience: Clean Banner (Pro options removed as requested) */}
            <div className="form-group" style={{ marginBottom: '16px' }}>
              <label className="form-label">Target Audience</label>
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '12px',
                  padding: '12px 14px',
                  background: 'var(--bg-dark)',
                  border: '1px solid var(--border)',
                  borderRadius: '10px',
                }}
              >
                <div
                  style={{
                    width: '32px',
                    height: '32px',
                    borderRadius: '8px',
                    background: 'var(--accent-light)',
                    color: 'var(--accent)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  <UsersIcon size={16} />
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: '13px', fontWeight: 600, color: 'var(--text-primary)' }}>
                    All Registered Explorers
                  </div>
                  <div style={{ fontSize: '11.5px', color: 'var(--text-secondary)' }}>
                    Delivered instantly to all active iOS & Android mobile devices
                  </div>
                </div>
                <Badge tone="green" style={{ fontSize: '11px', padding: '2px 8px' }}>
                  100% Reach
                </Badge>
              </div>
            </div>

            {/* Notification Title */}
            <div className="form-group" style={{ marginBottom: '16px' }}>
              <label className="form-label">
                Notification Title
                <span className="char-counter">{title.length}/60</span>
              </label>
              <input
                type="text"
                className="form-input"
                placeholder="e.g. Weekend Discovery: 5 Hidden Cafes in Town"
                value={title}
                maxLength={60}
                onChange={(e) => setTitle(e.target.value)}
                required
              />
            </div>

            {/* Notification Body */}
            <div className="form-group" style={{ marginBottom: '16px' }}>
              <label className="form-label">
                Notification Body
                <span className="char-counter">{message.length}/240</span>
              </label>
              <textarea
                className="form-textarea"
                placeholder="Enter push notification message here..."
                value={message}
                maxLength={240}
                onChange={(e) => setMessage(e.target.value)}
                required
                style={{ minHeight: '90px' }}
              />
            </div>

            {/* Live Interactive Mobile Phone Lock-Screen Preview */}
            <div className="mobile-preview-container">
              <div className="mobile-preview-top">
                <span className="mobile-preview-label">
                  <SmartphoneIcon size={13} /> Live Mobile Device Preview
                </span>
                <span className="mobile-preview-time-bar">
                  <span>9:41 AM</span>
                  <span>•</span>
                  <span>5G</span>
                </span>
              </div>

              <div className="mobile-push-notification">
                <div className="mobile-push-header">
                  <div className="mobile-push-appicon">n</div>
                  <span className="mobile-push-appname">nexARound</span>
                  <span className="mobile-push-time">now</span>
                </div>
                <div className="mobile-push-title">
                  {title.trim() || 'Notification Title'}
                </div>
                <div className="mobile-push-body">
                  {message.trim() || 'Your message will appear here on user lock screens and in the notification shade.'}
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div style={{ display: 'flex', gap: '10px', marginTop: '16px' }}>
              {(title || message) && (
                <button
                  type="button"
                  className="btn btn-ghost"
                  onClick={() => {
                    setTitle('');
                    setMessage('');
                  }}
                  disabled={sending}
                >
                  Clear
                </button>
              )}
              <button
                type="submit"
                className="btn btn-primary"
                style={{
                  flex: 1,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px',
                  padding: '12px',
                  fontSize: '14px',
                  fontWeight: 600,
                }}
                disabled={sending || !title.trim() || !message.trim()}
              >
                {sending ? (
                  <>Broadcasting to Devices… 📡</>
                ) : (
                  <>
                    <SendIcon size={16} /> Send Push Notification
                  </>
                )}
              </button>
            </div>
          </form>
        </Card>

        {/* Right: Broadcast History */}
        <Card style={{ margin: 0, background: 'var(--bg-dark)' }}>
          <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div className="card-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <BellIcon size={17} style={{ color: 'var(--accent)' }} /> Broadcast History
            </div>
            <button
              className="icon-btn"
              title="Refresh history"
              onClick={loadHistory}
              disabled={loadingHistory}
            >
              <RefreshIcon size={15} className={loadingHistory ? 'spin-anim' : ''} />
            </button>
          </div>

          {/* Search history */}
          <div style={{ marginBottom: '14px', position: 'relative' }}>
            <input
              type="text"
              className="form-input"
              placeholder="Search past broadcasts…"
              value={historySearch}
              onChange={(e) => setHistorySearch(e.target.value)}
              style={{ fontSize: '12.5px', paddingLeft: '32px' }}
            />
            <div
              style={{
                position: 'absolute',
                left: '10px',
                top: '50%',
                transform: 'translateY(-50%)',
                color: 'var(--text-secondary)',
                pointerEvents: 'none',
              }}
            >
              <SearchIcon size={14} />
            </div>
          </div>

          {/* History List */}
          <div style={{ maxHeight: '680px', overflowY: 'auto' }}>
            {recentBroadcasts.length === 0 && !loadingHistory && (
              <div style={{ padding: '36px 16px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: '13px' }}>
                No broadcasts sent yet.
              </div>
            )}

            {filteredHistory.map((b) => (
              <div
                key={b.id}
                className="broadcast-item-card"
                onClick={() => openDetail(b)}
                title="Click to view delivery breakdown"
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '10px' }}>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{ fontSize: '13.5px', fontWeight: 600, color: 'var(--text-primary)', marginBottom: '3px' }}>
                      {b.title}
                    </div>
                    {b.body && (
                      <div
                        style={{
                          fontSize: '12px',
                          color: 'var(--text-secondary)',
                          whiteSpace: 'nowrap',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          marginBottom: '8px',
                        }}
                      >
                        {b.body}
                      </div>
                    )}
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                      <Badge tone="blue" style={{ fontSize: '10px', padding: '2px 7px' }}>
                        {b.target}
                      </Badge>
                      <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>{b.date}</span>
                    </div>
                  </div>

                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '4px' }}>
                    {typeof b.sent === 'number' && (
                      <span
                        style={{
                          fontSize: '11px',
                          fontWeight: 700,
                          padding: '3px 8px',
                          borderRadius: '12px',
                          background: b.sent > 0 ? '#e6f7ee' : '#f0f0f3',
                          color: b.sent > 0 ? '#0a7d3c' : '#777',
                        }}
                      >
                        {b.sent} sent
                      </span>
                    )}
                    {b.failed > 0 && (
                      <span
                        style={{
                          fontSize: '10.5px',
                          fontWeight: 600,
                          padding: '2px 6px',
                          borderRadius: '10px',
                          background: '#fdecea',
                          color: '#c0392b',
                        }}
                      >
                        {b.failed} failed
                      </span>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>

      {/* Broadcast detail popup: who received it, who failed, with user search */}
      {detailBc && (
        <div
          onClick={closeDetail}
          style={{
            position: 'fixed',
            inset: 0,
            background: 'rgba(0,0,0,0.5)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
            padding: '20px',
          }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="card"
            style={{
              margin: 0,
              width: '100%',
              maxWidth: '620px',
              maxHeight: '85vh',
              display: 'flex',
              flexDirection: 'column',
            }}
          >
            <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '12px' }}>
              <div style={{ minWidth: 0 }}>
                <div className="card-title" style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {detailBc.title}
                </div>
                <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '4px' }}>
                  Delivery breakdown · {detail?.total_recipients ?? '…'} recipients
                </div>
              </div>
              <button
                onClick={closeDetail}
                className="btn"
                style={{ background: 'transparent', border: 'none', padding: '4px', cursor: 'pointer', color: 'var(--text-secondary)' }}
              >
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
                  onClick={() => changeDetailStatus(s.key)}
                  style={{
                    cursor: 'pointer',
                    padding: '7px 12px',
                    borderRadius: '10px',
                    fontSize: '12px',
                    border: detailStatus === s.key ? '2px solid var(--accent)' : '1px solid rgba(0,0,0,0.1)',
                    background: detailStatus === s.key ? 'var(--accent-light)' : 'var(--bg-card)',
                    color: 'var(--text-primary)',
                    fontWeight: 600,
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
              onChange={(e) => changeDetailSearch(e.target.value)}
              style={{ marginBottom: '12px' }}
            />

            <div style={{ overflowY: 'auto', flex: 1, border: '1px solid rgba(0,0,0,0.06)', borderRadius: '10px' }}>
              {detailLoading && (
                <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: '13px' }}>
                  Loading…
                </div>
              )}
              {!detailLoading && detail && detail.recipients.length === 0 && (
                <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: '13px' }}>
                  No recipients match.
                </div>
              )}
              {!detailLoading &&
                detail &&
                detail.recipients.map((r) => (
                  <div
                    key={r.user_id}
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      padding: '11px 14px',
                      borderBottom: '1px solid rgba(0,0,0,0.05)',
                    }}
                  >
                    <div style={{ minWidth: 0 }}>
                      <div
                        style={{
                          fontSize: '13.5px',
                          fontWeight: 600,
                          whiteSpace: 'nowrap',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                        }}
                      >
                        {r.name}
                      </div>
                      <div
                        style={{
                          fontSize: '11.5px',
                          color: 'var(--text-secondary)',
                          whiteSpace: 'nowrap',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                        }}
                      >
                        {r.email}
                      </div>
                    </div>
                    <span
                      style={{
                        ...(STATUS_STYLE[r.push_status] || STATUS_STYLE.pending),
                        fontSize: '11px',
                        fontWeight: 700,
                        padding: '4px 10px',
                        borderRadius: '20px',
                        whiteSpace: 'nowrap',
                        marginLeft: '12px',
                      }}
                    >
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
