import { Link } from 'react-router-dom';
import { useApi, mediaUrl } from '../api';
import { useAuth } from '../auth';
import { RESYNC, useLiveEvent } from '../live';
import { TicketIcon, InboxIcon, ClockIcon, CheckIcon, PlusIcon, EditIcon } from '../components/Icons';
import { Avatar } from '../components/Kit';
import { EmptyState, EnquiryStatusPill, ListRow, Loader, StatusPill } from '../components/Lists';
import {
  formatAge, formatDateTime, formatDay, guestsLabel,
  formatPrice, basisLabel, visibility, visibilityTone,
} from '../format';

// The dashboard shows the first few; the rest are one click away.
const PACKAGE_PREVIEW = 5;

export default function Dashboard() {
  const { me } = useAuth();
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
      sub: `${stats?.packages_total ?? 0} in total`, to: '/packages' },
    { label: 'New enquiries', value: stats?.enquiries_new, Icon: InboxIcon,
      sub: newCount > 0 ? 'waiting for a reply →' : 'waiting for a reply', to: '/enquiries?status=new', warm: newCount > 0 },
    { label: 'Last 30 days', value: stats?.enquiries_last_30d, Icon: ClockIcon,
      sub: 'enquiries received', to: '/enquiries' },
    { label: 'All enquiries', value: stats?.enquiries_total, Icon: TicketIcon,
      sub: 'since you joined', to: '/enquiries' },
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
          <Link className="btn btn-ghost" to="/profile">
            <EditIcon size={15} /> Profile
          </Link>
          <Link className="btn btn-primary" to="/packages/new">
            <PlusIcon size={15} /> New package
          </Link>
        </div>
      </div>

      <div className="kpi-grid">
        {tiles.map(({ label, value, sub, Icon, to, warm }) => (
          <Link key={label} to={to} className={`kpi ${warm ? 'warm' : ''}`}>
            <span className="kpi-label"><Icon size={16} /> {label}</span>
            <span className="kpi-value">{value ?? '–'}</span>
            <span className="kpi-sub">{sub}</span>
          </Link>
        ))}
      </div>

      <div className="dash-cols">
        <section className="panel">
          <div className="panel-head">
            <span className="panel-title">Latest enquiries</span>
            <Link className="link-btn" to="/enquiries">See all</Link>
          </div>

          {!recent && <div className="panel-pad"><Loader /></div>}

          {recent?.enquiries.length === 0 && (
            <EmptyState icon={InboxIcon} title="No enquiries yet" pad={40}>
              They arrive here when a traveller asks about one of your packages.
            </EmptyState>
          )}

          {recent?.enquiries.map((e) => (
            <ListRow
              key={e.id}
              to={`/enquiries/${e.id}`}
              lead={<Avatar name={e.contact_name} />}
              title={e.contact_name}
              strong={e.status === 'new'}
              subs={[e.package_title_snapshot || 'General enquiry', guestsLabel(e.party_size), formatDay(e.preferred_date)]
                .filter(Boolean).join(' · ')}
              side={(
                <>
                  <span title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</span>
                  <EnquiryStatusPill status={e.status} />
                </>
              )}
            />
          ))}
        </section>

        <section className="panel">
          <div className="panel-head">
            <span className="panel-title">Your packages</span>
            <Link className="link-btn" to="/packages">Manage</Link>
          </div>

          {!packageData && <div className="panel-pad"><Loader /></div>}

          {packageData && packages.length === 0 && (
            <EmptyState
              icon={TicketIcon} title="List your first package" pad={40}
              action={(
                <Link className="btn btn-primary btn-sm" to="/packages/new">
                  <PlusIcon size={15} /> Add package
                </Link>
              )}
            >
              Each package appears in the app as its own experience travellers can enquire about.
            </EmptyState>
          )}

          {packages.slice(0, PACKAGE_PREVIEW).map((pkg) => (
            <ListRow
              key={pkg.id}
              to={`/packages/${pkg.id}`}
              lead={(
                <span className="dash-thumb">
                  {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={18} />}
                </span>
              )}
              title={pkg.title}
              subs={[formatPrice(pkg), pkg.price_amount != null && basisLabel(pkg.price_basis)].filter(Boolean).join(' · ')}
              side={<StatusPill tone={visibilityTone(pkg)}>{visibility(pkg)}</StatusPill>}
            />
          ))}
        </section>
      </div>
    </>
  );
}
