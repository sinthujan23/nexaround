import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useApi, apiPut, mediaUrl } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import { useToast } from '../toast';
import { PlusIcon, TicketIcon } from '../components/Icons';
import { Switch } from '../components/Kit';
import { EmptyState, ErrorBanner, Loader, SearchInput, StatusPill, Tabs } from '../components/Lists';
import {
  categoryLabel, categoryTone, basisLabel, formatPrice, formatDuration, visibility, visibilityTone,
} from '../format';
import { toPayload } from './packageForm';

/**
 * The package list. Editing is its own page (/packages/:id): the form has
 * five sections, which is a page's worth of work, not a drawer's.
 */
export default function Packages() {
  const navigate = useNavigate();
  const notify = useToast();
  const { data, error, refetch } = useApi('/partner/packages');
  const [packages, setPackages] = useState(null); // optimistic copy of data
  const list = packages ?? data?.packages ?? [];

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');

  // Changed elsewhere (another tab, another login, or NexAround). The
  // optimistic copy is dropped only once the fresh list has landed, so a
  // switch just flipped here does not blink back while the refetch is out.
  const [staleData, setStaleData] = useState(null);
  if (staleData && data !== staleData) {
    setStaleData(null);
    setPackages(null);
  }
  useLiveEvent(['packages.changed', 'account.changed', RESYNC], () => {
    setStaleData(data || {});
    refetch();
  });

  const toggleLive = async (pkg, isActive) => {
    // Optimistic, so the switch moves under the cursor.
    setPackages(list.map((p) => (p.id === pkg.id ? { ...p, is_active: isActive } : p)));
    try {
      const updated = await apiPut(`/partner/packages/${pkg.id}`, toPayload({ ...pkg, is_active: isActive }));
      setPackages((prev) => (prev || list).map((p) => (p.id === pkg.id ? updated : p)));
    } catch (err) {
      setPackages((prev) => (prev || list).map((p) => (p.id === pkg.id ? { ...p, is_active: !isActive } : p)));
      notify(`Could not update: ${err.message}`, 'error');
    }
  };

  const liveCount = list.filter((p) => p.is_active).length;
  const q = search.trim().toLowerCase();
  const filtered = list.filter((p) =>
    (statusFilter === 'all' || (statusFilter === 'live' ? p.is_active : !p.is_active))
    && (!q || [p.title, p.summary, categoryLabel(p.category)].some((f) => (f || '').toLowerCase().includes(q)))
  );

  const filters = [
    { value: 'all', label: 'All', count: list.length },
    { value: 'live', label: 'Live', count: liveCount },
    { value: 'hidden', label: 'Hidden', count: list.length - liveCount },
  ];

  const addButton = (
    <Link className="btn btn-primary btn-sm" to="/packages/new">
      <PlusIcon size={15} /> Add package
    </Link>
  );

  return (
    <>
      <div className="xp-toolbar">
        <Tabs items={filters} value={statusFilter} onChange={setStatusFilter} />
        <div className="xp-toolbar-right">
          <SearchInput value={search} onChange={setSearch} placeholder="Search your packages…" />
          {addButton}
        </div>
      </div>

      <ErrorBanner>{error}</ErrorBanner>

      {!data && !error && <Loader />}

      {data && list.length === 0 && (
        <EmptyState card pad={56} icon={TicketIcon} title="List your first package" action={addButton}>
          Each package appears in the app as its own experience travellers can enquire about.
        </EmptyState>
      )}

      {data && list.length > 0 && filtered.length === 0 && (
        <EmptyState card pad={48} title="Nothing matches">Try a different search or status.</EmptyState>
      )}

      {filtered.length > 0 && (
        <div className="pkg-grid">
          {filtered.map((pkg) => (
            <div
              key={pkg.id}
              className={`pkg-card ${pkg.is_published ? '' : 'is-hidden'}`}
              onClick={() => navigate(`/packages/${pkg.id}`)}
            >
              <div className="pkg-card-img">
                {pkg.photo_urls?.[0] ? <img src={mediaUrl(pkg.photo_urls[0])} alt="" /> : <TicketIcon size={28} />}
                <StatusPill tone={visibilityTone(pkg)}>{visibility(pkg)}</StatusPill>
              </div>
              <div className="pkg-card-body">
                <div className={`pkg-eyebrow tone-${categoryTone(pkg.category)}`}>{categoryLabel(pkg.category)}</div>
                <div className="pkg-card-title">{pkg.title}</div>
                {pkg.summary && <div className="pkg-card-vendor">{pkg.summary}</div>}
                <div className="pkg-card-foot">
                  <div>
                    <div className="pkg-price">{formatPrice(pkg)}</div>
                    <div className="sub">
                      {basisLabel(pkg.price_basis)}
                      {pkg.duration_minutes ? ` · ${formatDuration(pkg.duration_minutes)}` : ''}
                    </div>
                  </div>
                  <Switch checked={pkg.is_active} onChange={(v) => toggleLive(pkg, v)} label="Show in app" />
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}
