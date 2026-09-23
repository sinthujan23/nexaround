import { useApi } from '../api';
import { TicketIcon, InboxIcon, ClockIcon, CheckIcon, PlusIcon, GlobeIcon } from '../components/Icons';
import { STATUS_LABELS, STATUS_TONES, formatAge, formatDateTime, formatDay, guestsLabel } from '../format';

export default function Dashboard({ onNavigate, me }) {
  const { data: stats, loading } = useApi('/partner/stats');
  const { data: recent } = useApi('/partner/enquiries?page=1&page_size=5');

  const tiles = [
    { label: 'Packages live', value: stats?.packages_published ?? 0, Icon: CheckIcon,
      sub: `${stats?.packages_total ?? 0} in total`, page: 'packages', tone: 'teal' },
    { label: 'New enquiries', value: stats?.enquiries_new ?? 0, Icon: InboxIcon,
      sub: 'waiting for a reply', page: 'enquiries', tone: 'amber' },
    { label: 'Last 30 days', value: stats?.enquiries_last_30d ?? 0, Icon: ClockIcon,
      sub: 'enquiries received', page: 'enquiries', tone: 'blue' },
    { label: 'All enquiries', value: stats?.enquiries_total ?? 0, Icon: TicketIcon,
      sub: 'since you joined', page: 'enquiries', tone: 'violet' },
  ];

  const vendorName = me?.vendor_name || 'Partner';

  return (
    <>
      {loading && <div className="loader" />}

      {/* Unified Compact Partner Hero with Integrated Glass Stat Cards */}
      <div className="partner-hero-unified">
        <div className="partner-hero-overlay" />
        <div className="partner-hero-unified-body">
          {/* Left Column: Greeting & Actions */}
          <div className="partner-hero-left">
            <div className="partner-hero-meta">
              <span className="partner-hero-badge">
                <span className="pulse-dot" /> Experience Partner
              </span>
              {me?.vendor_is_active !== false && (
                <span className="partner-hero-status">
                  🟢 Live
                </span>
              )}
            </div>

            <h1 className="partner-hero-title-compact" title={vendorName}>
              Welcome back, {vendorName} 👋
            </h1>

            <p className="partner-hero-sub-compact">
              Manage your experience packages, respond to traveller inquiries, and track bookings.
            </p>

            <div className="partner-hero-actions-compact">
              <button className="partner-hero-btn primary" onClick={() => onNavigate('packages')}>
                <PlusIcon size={15} /> Packages
              </button>
              <button className="partner-hero-btn secondary" onClick={() => onNavigate('enquiries')}>
                <InboxIcon size={15} />
                <span>Enquiries</span>
                {(stats?.enquiries_new ?? 0) > 0 && (
                  <span className="partner-hero-btn-pill">{stats.enquiries_new} new</span>
                )}
              </button>
              <button className="partner-hero-btn ghost" onClick={() => onNavigate('profile')}>
                <GlobeIcon size={15} /> Profile
              </button>
            </div>
          </div>

          {/* Right Column: Integrated Compact Glass Stat Cards */}
          <div className="partner-hero-stats-compact">
            {tiles.map(({ label, value, sub, Icon, page, tone }) => (
              <div
                key={label}
                className={`stat-chip tone-${tone} ${tone === 'amber' && value > 0 ? 'highlight-pulse' : ''}`}
                onClick={() => onNavigate(page)}
                title={`View ${label}`}
              >
                <div className="stat-chip-top">
                  <div className="stat-chip-icon">
                    <Icon size={15} />
                  </div>
                  <div className="stat-chip-value">{value}</div>
                </div>
                <div className="stat-chip-label">{label}</div>
                <div className="stat-chip-sub">{sub}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="xp-pane" style={{ marginTop: 20 }}>
        <div className="xp-list-head" style={{ padding: '16px 20px' }}>
          <span className="card-title">Latest enquiries</span>
          <button className="btn btn-ghost btn-sm" onClick={() => onNavigate('enquiries')}>See all</button>
        </div>

        {(!recent || recent.enquiries.length === 0) && (
          <div className="xp-empty" style={{ padding: 40 }}>
            <InboxIcon size={32} />
            <strong>No enquiries yet</strong>
            They arrive here when a traveller asks about one of your packages.
          </div>
        )}

        {recent?.enquiries.map((e) => (
          <button
            key={e.id}
            className="xp-row"
            style={{ alignItems: 'flex-start', padding: '14px 20px' }}
            onClick={() => onNavigate('enquiries', e.id)}
          >
            <div className="xp-row-main">
              <div className={`xp-row-title ${e.status === 'new' ? 'strong' : ''}`}>{e.contact_name}</div>
              <div className="xp-row-sub">
                {[e.package_title_snapshot || 'General enquiry', guestsLabel(e.party_size), formatDay(e.preferred_date)]
                  .filter(Boolean).join(' · ')}
              </div>
            </div>
            <div className="xp-row-side">
              <span title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</span>
              <span className={`pill tone-${STATUS_TONES[e.status] || 'gray'}`}>{STATUS_LABELS[e.status] || e.status}</span>
            </div>
          </button>
        ))}
      </div>
    </>
  );
}
