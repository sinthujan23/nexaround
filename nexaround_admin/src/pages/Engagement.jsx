import React, { useState } from 'react';
import { UsersIcon, TimerIcon, CompassIcon, MegaphoneIcon, CheckIcon, CrossIcon, TrendingUpIcon } from '../components/Icons';

export default function Engagement() {
  const [title, setTitle] = useState('');
  const [message, setMessage] = useState('');
  const [targetPlan, setTargetPlan] = useState('all');
  const [sending, setSending] = useState(false);
  const [successMsg, setSuccessMsg] = useState('');

  // Mock Data
  const metrics = {
    daily_active_users: 14250,
    avg_session_length: '24m 12s',
    places_visited_count: 89340
  };

  const [recentBroadcasts, setRecentBroadcasts] = useState([
    { id: 1, title: 'Welcome to NexARound 2.0', target: 'All Explorers', date: 'Yesterday, 10:00 AM' },
    { id: 2, title: 'Exclusive Pro AR Filters Live', target: 'Pro Explorers Only', date: 'May 18, 2026' },
    { id: 3, title: 'Paris AR Tour Update', target: 'All Explorers', date: 'May 15, 2026' },
  ]);

  const handleBroadcast = (e) => {
    e.preventDefault();
    setSending(true);
    setSuccessMsg('');
    setTimeout(() => {
      setSuccessMsg('Announcement successfully broadcasted to users!');
      setRecentBroadcasts([{ 
        id: Date.now(), 
        title, 
        target: targetPlan === 'all' ? 'All Explorers' : targetPlan, 
        date: 'Just now' 
      }, ...recentBroadcasts]);
      setTitle('');
      setMessage('');
      setSending(false);
      
      setTimeout(() => setSuccessMsg(''), 5000);
    }, 1200);
  };

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
            {recentBroadcasts.map((b) => (
              <div className="modern-list-item" key={b.id} style={{ background: 'var(--bg-card)', padding: '16px', alignItems: 'flex-start' }}>
                <div className="list-item-main">
                  <div className="list-item-icon" style={{ background: 'var(--accent-light)', color: 'var(--accent)', borderRadius: '50%', width: '32px', height: '32px' }}>
                    <MegaphoneIcon size={14} />
                  </div>
                  <div className="list-item-content">
                    <div className="list-item-title" style={{ fontSize: '13.5px' }}>{b.title}</div>
                    <div className="list-item-meta" style={{ marginTop: '2px' }}>
                      <span className="badge badge-blue" style={{ fontSize: '9px', padding: '2px 6px' }}>{b.target}</span>
                      <span style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>{b.date}</span>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
