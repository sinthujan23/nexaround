import { useApi } from '../api';
import { TicketIcon, InboxIcon, ClockIcon, CheckIcon } from '../components/Icons';
import { STATUS_LABELS, formatAge, formatDateTime, formatDay, guestsLabel } from '../format';

export default function Dashboard({ onNavigate }) {
  const { data: stats, loading } = useApi('/partner/stats');
  const { data: recent } = useApi('/partner/enquiries?page=1&page_size=5');

  const tiles = [
    { label: 'Packages live', value: stats?.packages_published ?? 0, Icon: CheckIcon,
      sub: `${stats?.packages_total ?? 0} in total`, page: 'packages' },
    { label: 'New enquiries', value: stats?.enquiries_new ?? 0, Icon: InboxIcon,
      sub: 'waiting for a reply', page: 'enquiries' },
    { label: 'Last 30 days', value: stats?.enquiries_last_30d ?? 0, Icon: ClockIcon,
      sub: 'enquiries received', page: 'enquiries' },
    { label: 'All enquiries', value: stats?.enquiries_total ?? 0, Icon: TicketIcon,
      sub: 'since you joined', page: 'enquiries' },
  ];

  return (
    <>
      {loading && <div className="loader" />}

      <div className="stats-grid">
        {tiles.map(({ label, value, sub, Icon, page }) => (
          <div key={label} className="stat-card" style={{ cursor: 'pointer' }} onClick={() => onNavigate(page)}>
            <div className="stat-icon"><Icon size={20} /></div>
            <div className="stat-value">{value}</div>
            <div className="stat-label">{label}</div>
            <div className="stat-change">{sub}</div>
          </div>
        ))}
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
            <span className={`dot dot-${e.status}`} style={{ marginTop: 6 }} title={STATUS_LABELS[e.status]} />
            <div className="xp-row-main">
              <div className={`xp-row-title ${e.status === 'new' ? 'strong' : ''}`}>{e.contact_name}</div>
              <div className="xp-row-sub">
                {[e.package_title_snapshot || 'General enquiry', guestsLabel(e.party_size), formatDay(e.preferred_date)]
                  .filter(Boolean).join(' · ')}
              </div>
            </div>
            <div className="xp-row-side" title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</div>
          </button>
        ))}
      </div>
    </>
  );
}
