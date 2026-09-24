import { useApi, mediaUrl } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import { TicketIcon, InboxIcon, ClockIcon, CheckIcon, PlusIcon, EditIcon } from '../components/Icons';
import { Avatar } from '../components/Kit';
import {
  STATUS_LABELS, STATUS_TONES, formatAge, formatDateTime, formatDay, guestsLabel,
  formatPrice, basisLabel, visibility, visibilityTone,
} from '../format';

// The dashboard shows the first few; the rest are one click away.
const PACKAGE_PREVIEW = 5;

export default function Dashboard({ onNavigate, me }) {
  const { data: stats, refetch: refetchStats } = useApi('/partner/stats');
  const { data: recent, refetch: refetchRecent } = useApi('/partner/enquiries?page=1&page_size=5');
  const { data: packageData, refetch: refetchPackages } = useApi('/partner/packages');

  useLiveEvent(
    ['enquiry.created', 'enquiry.updated', 'packages.changed', 'account.changed', RESYNC],
    ({ type }) => {
      refetchStats();
      if (type !== 'packages.changed' && type !== 'account.changed') refetchRecent();
      if (!type.startsWith('enquiry.')) refetchPackages();
    },
  );
  const packages = packageData?.packages || [];
  const newCount = stats?.enquiries_new ?? 0;

  const tiles = [
    { label: 'Packages live', value: stats?.packages_published, Icon: CheckIcon,
      sub: `${stats?.packages_total ?? 0} in total`, page: 'packages' },
    { label: 'New enquiries', value: stats?.enquiries_new, Icon: InboxIcon,
      sub: newCount > 0 ? 'waiting for a reply →' : 'waiting for a reply', page: 'enquiries', warm: newCount > 0 },
    { label: 'Last 30 days', value: stats?.enquiries_last_30d, Icon: ClockIcon,
      sub: 'enquiries received', page: 'enquiries' },
    { label: 'All enquiries', value: stats?.enquiries_total, Icon: TicketIcon,
      sub: 'since you joined', page: 'enquiries' },
  ];

  const vendorName = me?.vendor_name || 'Partner';

  return (
    <>
      <div className="dash-top">
        <div className="dash-greeting">
          <h1 className="dash-title">Welcome back, {vendorName}</h1>
          {/* A hidden listing already gets the red banner above the page. */}
          {me?.vendor_is_active && (
            <p className="dash-sub"><span className="live-dot" /> Your listing is live on nexARound</p>
          )}
        </div>
        <div className="dash-actions">
          <button className="btn btn-ghost" onClick={() => onNavigate('profile')}>
            <EditIcon size={15} /> Profile
          </button>
          <button className="btn btn-primary" onClick={() => onNavigate('packages', 'new')}>
            <PlusIcon size={15} /> New package
          </button>
        </div>
      </div>

      <div className="kpi-grid">
        {tiles.map(({ label, value, sub, Icon, page, warm }) => (
          <button key={label} type="button" className={`kpi ${warm ? 'warm' : ''}`} onClick={() => onNavigate(page)}>
            <span className="kpi-label"><Icon size={16} /> {label}</span>
            <span className="kpi-value">{value ?? '–'}</span>
            <span className="kpi-sub">{sub}</span>
          </button>
        ))}
      </div>

      <div className="dash-cols">
        <section className="panel">
          <div className="panel-head">
            <span className="panel-title">Latest enquiries</span>
            <button className="link-btn" onClick={() => onNavigate('enquiries')}>See all</button>
          </div>

          {!recent && <div className="panel-pad"><div className="loader" /></div>}

          {recent?.enquiries.length === 0 && (
            <div className="xp-empty" style={{ padding: 40 }}>
              <InboxIcon size={32} />
              <strong>No enquiries yet</strong>
              They arrive here when a traveller asks about one of your packages.
            </div>
          )}

          {recent?.enquiries.map((e) => (
            <button key={e.id} className="dash-row" onClick={() => onNavigate('enquiries', e.id)}>
              <Avatar name={e.contact_name} />
              <div className="dash-row-main">
                <div className={`dash-row-title ${e.status === 'new' ? 'strong' : ''}`}>{e.contact_name}</div>
                <div className="dash-row-sub">
                  {[e.package_title_snapshot || 'General enquiry', guestsLabel(e.party_size), formatDay(e.preferred_date)]
                    .filter(Boolean).join(' · ')}
                </div>
              </div>
              <div className="dash-row-side">
                <span title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</span>
                <span className={`pill tone-${STATUS_TONES[e.status] || 'gray'}`}>{STATUS_LABELS[e.status] || e.status}</span>
              </div>
            </button>
          ))}
        </section>

        <section className="panel">
          <div className="panel-head">
            <span className="panel-title">Your packages</span>
            <button className="link-btn" onClick={() => onNavigate('packages')}>Manage</button>
          </div>

          {!packageData && <div className="panel-pad"><div className="loader" /></div>}

          {packageData && packages.length === 0 && (
            <div className="xp-empty" style={{ padding: 40 }}>
              <TicketIcon size={32} />
              <strong>List your first package</strong>
              Each package appears in the app as its own experience travellers can enquire about.
              <div style={{ marginTop: 12 }}>
                <button className="btn btn-primary btn-sm" onClick={() => onNavigate('packages', 'new')}>
                  <PlusIcon size={15} /> Add package
                </button>
              </div>
            </div>
          )}

          {packages.slice(0, PACKAGE_PREVIEW).map((pkg) => (
            <button key={pkg.id} className="dash-row" onClick={() => onNavigate('packages', pkg.id)}>
              <span className="dash-thumb">
                {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={18} />}
              </span>
              <div className="dash-row-main">
                <div className="dash-row-title">{pkg.title}</div>
                <div className="dash-row-sub">
                  {[formatPrice(pkg), pkg.price_amount != null && basisLabel(pkg.price_basis)].filter(Boolean).join(' · ')}
                </div>
              </div>
              <span className={`pill tone-${visibilityTone(pkg)}`}>{visibility(pkg)}</span>
            </button>
          ))}
        </section>
      </div>
    </>
  );
}
