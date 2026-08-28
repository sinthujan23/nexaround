import { useState, useEffect } from 'react';
import { useApi, apiPost } from '../api';
import { SearchIcon, CheckIcon, CrossIcon, UsersIcon } from '../components/Icons';

export default function Users() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Debounce search query to avoid spamming requests
  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1); // Reset to page 1 on new search
    }, 300);
    return () => clearTimeout(handler);
  }, [search]);

  const { data, loading, error, refetch } = useApi(`/admin/users?page=${page}&page_size=10&search=${encodeURIComponent(debouncedSearch)}`);

  const handleVerify = async (userId) => {
    try {
      await apiPost(`/admin/users/${userId}/verify`);
      refetch();
    } catch (err) {
      alert(`Verification failed: ${err.message}`);
    }
  };

  const handleToggleStatus = async (userId) => {
    try {
      await apiPost(`/admin/users/${userId}/toggle-active`);
      refetch();
    } catch (err) {
      alert(`Failed to update status: ${err.message}`);
    }
  };

  if (error) {
    return (
      <div className="login-error" style={{ margin: '20px' }}>
        Failed to load explorers: {error}
      </div>
    );
  }

  const users = data?.users || [];
  const total = data?.total || 0;
  const totalPages = Math.ceil(total / 10) || 1;

  return (
    <div className="approvals-modern-container">
      {/* Premium Hero Banner (Compact) */}
      <div className="approvals-hero" style={{
        background: 'linear-gradient(135deg, var(--accent) 0%, var(--accent-2) 100%)',
        borderRadius: '16px',
        padding: '16px 24px',
        color: 'white',
        marginBottom: '16px',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        boxShadow: '0 8px 24px rgba(0, 122, 124, 0.12)'
      }}>
        <div>
          <h2 style={{ fontSize: '20px', fontWeight: 800, margin: 0, letterSpacing: '-0.5px' }}>Registered Explorers</h2>
          <p style={{ margin: '4px 0 0 0', opacity: 0.9, fontSize: '13px', fontWeight: 500 }}>
            You have <strong style={{ color: '#fff', background: 'rgba(255,255,255,0.2)', padding: '2px 8px', borderRadius: '12px' }}>{total}</strong> registered explorers on the platform.
          </p>
        </div>
      </div>

      <div className="card modern-card" style={{ border: 'none', padding: '0', background: 'transparent', boxShadow: 'none' }}>
        <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: 'none', paddingBottom: 0 }}>
          <div className="card-title" style={{ fontSize: '18px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <UsersIcon size={18} style={{ color: 'var(--accent)' }} />
            All Explorers
          </div>
          <div className="search-bar">
            <SearchIcon size={16} style={{ color: 'var(--text-secondary)' }} />
            <input
              placeholder="Search by name or email..."
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
        </div>

        <div className="modern-list-container" style={{ marginTop: '20px' }}>
          {loading && users.length === 0 ? (
            <div className="empty-state">
              <div className="loader"></div>
              <p>Retrieving explorer profiles...</p>
            </div>
          ) : users.length === 0 ? (
            <div className="empty-state">
              <div className="empty-icon">
                <SearchIcon size={28} />
              </div>
              <h3 style={{ margin: '0 0 4px 0', fontSize: '16px', color: 'var(--text-primary)' }}>No explorers found</h3>
              <p style={{ margin: 0, fontSize: '13px' }}>We couldn't find any users matching your search query.</p>
            </div>
          ) : (
            <>
              <div className="modern-list">
                {users.map(u => {
                  const joinedDate = u.created_at
                    ? new Date(u.created_at).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric', timeZone: 'Asia/Colombo' })
                    : 'Unknown';
                  const avatarLetter = u.display_name ? u.display_name[0].toUpperCase() : 'E';
                  const travelStyle = u.preferences?.travel_style
                    ? u.preferences.travel_style.charAt(0).toUpperCase() + u.preferences.travel_style.slice(1)
                    : 'Explorer';

                  return (
                    <div key={u.id} className="modern-list-item" style={{ cursor: 'default' }}>
                      <div className="list-item-main" style={{ gap: '16px' }}>
                        {u.avatar_url ? (
                          <img src={u.avatar_url} alt={u.display_name} style={{ width: '40px', height: '40px', borderRadius: '50%', objectFit: 'cover', flexShrink: 0 }} />
                        ) : (
                          <div className="user-avatar" style={{ width: '40px', height: '40px', fontSize: '15px', flexShrink: 0 }}>{avatarLetter}</div>
                        )}
                        <div className="list-item-content">
                          <div className="list-item-title" style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                            {u.display_name || 'Explorer'}
                            {u.is_verified && <CheckIcon size={14} style={{ color: 'var(--accent)' }} title="Verified Pro" />}
                            {!u.is_active && <span className="badge badge-red" style={{ fontSize: '9px', padding: '2px 6px' }}>Suspended</span>}
                          </div>
                          <div className="list-item-meta">
                            <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{u.email}</span>
                            <span style={{ fontSize: '10px', color: 'var(--border-hover)', opacity: 0.5 }}>•</span>
                            <span className="badge badge-ghost" style={{ fontSize: '9px', padding: '2px 6px' }}>{u.is_verified ? 'Pro Master' : travelStyle}</span>
                            <span style={{ fontSize: '10px', color: 'var(--border-hover)', opacity: 0.5 }}>•</span>
                            <span className="list-item-loc">Joined {joinedDate}</span>
                          </div>
                        </div>
                      </div>
                      <div className="list-item-actions" style={{ opacity: 1 }}>
                        <div style={{ display: 'flex', gap: '6px' }}>
                          {!u.is_verified && (
                            <button className="action-btn approve" onClick={() => handleVerify(u.id)} style={{ padding: '6px 12px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                              <CheckIcon size={12} /> Verify
                            </button>
                          )}
                          <button
                            className={`action-btn ${u.is_active ? 'reject' : 'approve'}`}
                            onClick={() => handleToggleStatus(u.id)}
                            style={{ padding: '6px 12px', display: 'flex', alignItems: 'center', gap: '4px' }}
                          >
                            {u.is_active ? <><CrossIcon size={12} /> Suspend</> : <><CheckIcon size={12} /> Activate</>}
                          </button>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Pagination Controls */}
              {totalPages > 1 && (
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '20px', padding: '0 10px' }}>
                  <span style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
                    Page {page} of {totalPages}
                  </span>
                  <div style={{ display: 'flex', gap: '10px' }}>
                    <button
                      className="btn btn-ghost"
                      style={{ padding: '6px 12px', fontSize: '12px' }}
                      onClick={() => setPage(p => Math.max(1, p - 1))}
                      disabled={page === 1}
                    >
                      Previous
                    </button>
                    <button
                      className="btn btn-ghost"
                      style={{ padding: '6px 12px', fontSize: '12px' }}
                      onClick={() => setPage(p => Math.min(totalPages, p + 1))}
                      disabled={page === totalPages}
                    >
                      Next
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
