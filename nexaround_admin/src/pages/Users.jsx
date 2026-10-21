import { useState, useEffect, useRef } from 'react';
import { useApi, apiPost } from '../api';
import {
  SearchIcon,
  CheckIcon,
  CrossIcon,
  UsersIcon,
  FilterIcon,
  ChevronDownIcon,
  ArrowUpDownIcon,
} from '../components/Icons';
import { HeroBanner, HeroCount, SearchBar, Loading, EmptyState, Badge, PageError } from '../components/Kit';
import ExplorerActivity from '../components/ExplorerActivity';

const DATE_LABELS = {
  today: 'Today',
  this_week: 'Last 7 Days',
  this_month: 'Last 30 Days',
  custom: 'Custom Range',
};

export default function Users() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [dateFilter, setDateFilter] = useState('all');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [sortOrder, setSortOrder] = useState('desc');
  const [filterMenuOpen, setFilterMenuOpen] = useState(false);
  const filterPopoverRef = useRef(null);

  // Close filter popover when clicking outside
  useEffect(() => {
    function handleClickOutside(e) {
      if (filterPopoverRef.current && !filterPopoverRef.current.contains(e.target)) {
        setFilterMenuOpen(false);
      }
    }
    if (filterMenuOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [filterMenuOpen]);

  // Debounce search query to avoid spamming requests
  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(1); // Reset to page 1 on new search
    }, 300);
    return () => clearTimeout(handler);
  }, [search]);

  // Build query string for API
  const queryParams = new URLSearchParams({
    page: String(page),
    page_size: '10',
  });
  if (debouncedSearch) queryParams.set('search', debouncedSearch);
  if (status !== 'all') queryParams.set('status', status);
  if (dateFilter !== 'all' && dateFilter !== 'custom') queryParams.set('date_filter', dateFilter);
  if (startDate) queryParams.set('start_from', startDate);
  if (endDate) queryParams.set('end_to', endDate);
  if (sortOrder !== 'desc') queryParams.set('sort_order', sortOrder);

  const { data, loading, error, refetch } = useApi(`/admin/users?${queryParams.toString()}`);

  const handleToggleStatus = async (userId) => {
    try {
      await apiPost(`/admin/users/${userId}/toggle-active`);
      refetch();
    } catch (err) {
      alert(`Failed to update status: ${err.message}`);
    }
  };

  const formatJoinedDateTime = (isoStr) => {
    if (!isoStr) return 'Unknown';
    try {
      let s = String(isoStr).trim();
      // Ensure UTC ISO strings without explicit timezone offsets are correctly parsed
      if (!s.endsWith('Z') && !/[+-]\d{2}(:\d{2})?$/.test(s)) {
        s += 'Z';
      }
      const d = new Date(s);
      if (isNaN(d.getTime())) return isoStr;

      const dateStr = d.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        timeZone: 'Asia/Colombo',
      });
      const timeStr = d.toLocaleTimeString('en-US', {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZone: 'Asia/Colombo',
      });
      return `${dateStr} at ${timeStr} (SLST)`;
    } catch {
      return isoStr;
    }
  };

  if (error) {
    return <PageError error={error} onRetry={refetch} title="Unable to Load Explorers">Failed to load explorers: {error}</PageError>;
  }

  const users = data?.users || [];
  const total = data?.total || 0;
  const totalPages = Math.ceil(total / 10) || 1;
  const extraFiltersCount =
    (dateFilter !== 'all' ? 1 : 0) +
    (startDate || endDate ? 1 : 0);

  const hasActiveFilters =
    status !== 'all' ||
    dateFilter !== 'all' ||
    Boolean(startDate) ||
    Boolean(endDate) ||
    Boolean(search) ||
    sortOrder !== 'desc';

  return (
    <div className="approvals-modern-container">
      {/* Premium Hero Banner (Compact) */}
      <HeroBanner title="Registered Explorers">
        You have <HeroCount>{total}</HeroCount> registered explorers on the platform.
      </HeroBanner>

      <ExplorerActivity />

      <div className="card modern-card" style={{ border: 'none', padding: '0', background: 'transparent', boxShadow: 'none' }}>
        <div className="card-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: 'none', paddingBottom: 0 }}>
          <div className="card-title" style={{ fontSize: '18px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <UsersIcon size={18} style={{ color: 'var(--accent)' }} />
            All Explorers
          </div>
          <SearchBar value={search} onChange={setSearch} placeholder="Search by name or email..." />
        </div>

        {/* Modern Segmented Control & Action Toolbar (Linear & GitHub style) */}
        <div className="users-filter-toolbar">
          {/* Left: Segmented Tabs */}
          <div className="segmented-tabs" role="tablist">
            <button
              type="button"
              className={`segmented-tab ${status === 'all' ? 'active' : ''}`}
              onClick={() => {
                setStatus('all');
                setPage(1);
              }}
              role="tab"
              aria-selected={status === 'all'}
            >
              <span>All Explorers</span>
              <span className="tab-count">{total}</span>
            </button>

            <button
              type="button"
              className={`segmented-tab ${status === 'active' ? 'active' : ''}`}
              onClick={() => {
                setStatus('active');
                setPage(1);
              }}
              role="tab"
              aria-selected={status === 'active'}
            >
              <span className="tab-status-dot dot-active" />
              <span>Active</span>
            </button>

            <button
              type="button"
              className={`segmented-tab ${status === 'suspended' ? 'active' : ''}`}
              onClick={() => {
                setStatus('suspended');
                setPage(1);
              }}
              role="tab"
              aria-selected={status === 'suspended'}
            >
              <span className="tab-status-dot dot-suspended" />
              <span>Suspended</span>
            </button>
          </div>

          {/* Right: Actions Group (Filter Popover, Sort, Timezone) */}
          <div className="users-actions-group">
            {/* Filter Popover Anchor */}
            <div className="filter-popover-anchor" ref={filterPopoverRef}>
              <button
                type="button"
                className={`filter-dropdown-btn ${extraFiltersCount > 0 ? 'has-filters' : ''}`}
                onClick={() => setFilterMenuOpen(prev => !prev)}
                aria-expanded={filterMenuOpen}
                title="Open advanced filter options"
              >
                <FilterIcon size={14} />
                <span>Filters</span>
                {extraFiltersCount > 0 && (
                  <span className="filter-badge-count">{extraFiltersCount}</span>
                )}
                <ChevronDownIcon size={13} className={`chevron-rotate ${filterMenuOpen ? 'open' : ''}`} />
              </button>

              {filterMenuOpen && (
                <div className="filter-popover-menu" role="dialog" aria-label="Filter options">
                  <div className="filter-popover-header">
                    <div className="popover-title">
                      <FilterIcon size={13} style={{ color: 'var(--accent)' }} />
                      <span>Refine Explorers</span>
                    </div>
                    {extraFiltersCount > 0 && (
                      <button
                        type="button"
                        className="filter-reset-link"
                        onClick={() => {
                          setDateFilter('all');
                          setStartDate('');
                          setEndDate('');
                          setPage(1);
                        }}
                      >
                        Reset filters
                      </button>
                    )}
                  </div>

                  {/* Joined Date Filter */}
                  <div className="filter-popover-section">
                    <span className="filter-section-title">Join Period</span>
                    <div className="filter-pill-grid">
                      {[
                        { id: 'all', label: 'All Time' },
                        { id: 'today', label: 'Today' },
                        { id: 'this_week', label: 'Last 7 Days' },
                        { id: 'this_month', label: 'Last 30 Days' },
                        { id: 'custom', label: 'Custom Range' },
                      ].map(opt => (
                        <button
                          key={opt.id}
                          type="button"
                          className={`filter-option-pill ${dateFilter === opt.id ? 'active' : ''}`}
                          onClick={() => {
                            setDateFilter(opt.id);
                            if (opt.id !== 'custom') {
                              setStartDate('');
                              setEndDate('');
                            }
                            setPage(1);
                          }}
                        >
                          {opt.label}
                        </button>
                      ))}
                    </div>

                    {dateFilter === 'custom' && (
                      <div className="custom-date-inputs">
                        <div className="date-field">
                          <label>From</label>
                          <input
                            type="date"
                            className="form-input filter-date-input"
                            value={startDate}
                            onChange={e => { setStartDate(e.target.value); setPage(1); }}
                            max={endDate || undefined}
                          />
                        </div>
                        <div className="date-field">
                          <label>To</label>
                          <input
                            type="date"
                            className="form-input filter-date-input"
                            value={endDate}
                            onChange={e => { setEndDate(e.target.value); setPage(1); }}
                            min={startDate || undefined}
                          />
                        </div>
                      </div>
                    )}
                  </div>

                  <div className="filter-popover-footer">
                    <button
                      type="button"
                      className="btn btn-primary"
                      style={{ width: '100%', padding: '7px 12px', fontSize: '12px' }}
                      onClick={() => setFilterMenuOpen(false)}
                    >
                      Done
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* Sort Toggle Button */}
            <button
              type="button"
              className="filter-sort-btn"
              onClick={() => {
                setSortOrder(prev => (prev === 'desc' ? 'asc' : 'desc'));
                setPage(1);
              }}
              title={`Sorting: ${sortOrder === 'desc' ? 'Newest First' : 'Oldest First'}. Click to toggle.`}
            >
              <ArrowUpDownIcon size={13} />
              <span>{sortOrder === 'desc' ? 'Newest First' : 'Oldest First'}</span>
            </button>

            {/* Timezone Indicator */}
            <Badge
              tone="ghost"
              style={{ fontSize: '11px', display: 'inline-flex', alignItems: 'center', gap: '5px', padding: '5px 9px', fontWeight: 600 }}
              title="All dates and times are presented in Sri Lanka Standard Time (Asia/Colombo, UTC+5:30)"
            >
              <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: 'var(--accent)' }}></span>
              SLST
            </Badge>
          </div>
        </div>

        {/* Active Filter Chips / Pills */}
        {hasActiveFilters && (
          <div className="filter-active-chips-bar">
            <span className="chips-label">Active:</span>

            {status !== 'all' && (
              <span className="filter-chip">
                <span>Status: {status === 'active' ? 'Active' : 'Suspended'}</span>
                <button
                  type="button"
                  className="filter-chip-remove"
                  onClick={() => { setStatus('all'); setPage(1); }}
                  title="Remove status filter"
                >
                  <CrossIcon size={10} />
                </button>
              </span>
            )}

            {dateFilter !== 'all' && dateFilter !== 'custom' && (
              <span className="filter-chip">
                <span>Joined: {DATE_LABELS[dateFilter]}</span>
                <button
                  type="button"
                  className="filter-chip-remove"
                  onClick={() => { setDateFilter('all'); setPage(1); }}
                  title="Remove date filter"
                >
                  <CrossIcon size={10} />
                </button>
              </span>
            )}

            {dateFilter === 'custom' && (startDate || endDate) && (
              <span className="filter-chip">
                <span>Date: {startDate || 'Start'} → {endDate || 'Now'}</span>
                <button
                  type="button"
                  className="filter-chip-remove"
                  onClick={() => {
                    setDateFilter('all');
                    setStartDate('');
                    setEndDate('');
                    setPage(1);
                  }}
                  title="Remove custom date range"
                >
                  <CrossIcon size={10} />
                </button>
              </span>
            )}

            {debouncedSearch && (
              <span className="filter-chip">
                <span>Search: "{debouncedSearch}"</span>
                <button
                  type="button"
                  className="filter-chip-remove"
                  onClick={() => { setSearch(''); setPage(1); }}
                  title="Clear search query"
                >
                  <CrossIcon size={10} />
                </button>
              </span>
            )}

            <button
              type="button"
              className="filter-clear-all-btn"
              onClick={() => {
                setStatus('all');
                setDateFilter('all');
                setStartDate('');
                setEndDate('');
                setSortOrder('desc');
                setSearch('');
                setPage(1);
              }}
            >
              Clear all
            </button>
          </div>
        )}

        <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '10px' }}>
          <span style={{ fontSize: '12.5px', color: 'var(--text-secondary)' }}>
            Showing <strong>{users.length}</strong> of <strong>{total}</strong> explorers
          </span>
        </div>

        <div className="modern-list-container" style={{ marginTop: '20px' }}>
          {loading && users.length === 0 ? (
            <Loading>Retrieving explorer profiles...</Loading>
          ) : users.length === 0 ? (
            <EmptyState icon={<SearchIcon size={28} />} title="No explorers found">
              {hasActiveFilters
                ? "We couldn't find any users matching your active filters or search query."
                : "We couldn't find any users registered on the platform yet."}
            </EmptyState>
          ) : (
            <>
              <div className="modern-list">
                {users.map(u => {
                  const joinedDateTime = formatJoinedDateTime(u.created_at);
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
                            {!u.is_active && <Badge tone="red" style={{ fontSize: '9px', padding: '2px 6px' }}>Suspended</Badge>}
                          </div>
                          <div className="list-item-meta">
                            <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{u.email}</span>
                            <span style={{ fontSize: '10px', color: 'var(--border-hover)', opacity: 0.5 }}>•</span>
                            <Badge tone="ghost" style={{ fontSize: '9px', padding: '2px 6px' }}>{travelStyle}</Badge>
                            <span style={{ fontSize: '10px', color: 'var(--border-hover)', opacity: 0.5 }}>•</span>
                            <span
                              className="list-item-loc"
                              title="Sri Lanka Standard Time (Asia/Colombo, UTC+5:30)"
                            >
                              Joined {joinedDateTime}
                            </span>
                          </div>
                        </div>
                      </div>
                      <div className="list-item-actions" style={{ opacity: 1 }}>
                        <div style={{ display: 'flex', gap: '6px' }}>
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
