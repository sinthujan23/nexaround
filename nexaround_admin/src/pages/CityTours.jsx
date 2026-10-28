import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { mediaUrl, useApi } from '../api';
import { Badge, EmptyState, PageError, PageLoading, SearchBar } from '../components/Kit';
import { PlusIcon, RefreshIcon, RouteIcon } from '../components/Icons';
import { tourBadges } from '../cityTours';
import { isCreator } from '../session';

const FILTERS = [
  { key: '', label: 'All' },
  { key: 'draft', label: 'Drafts' },
  { key: 'pending', label: 'Waiting for review' },
  { key: 'changes_requested', label: 'Sent back' },
  { key: 'live', label: 'Live' },
];

const formatDate = (value) => (value
  ? new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  : '');

/**
 * City Tours guides. Admins see every guide, creators their own. With `queue`
 * it is the review queue: guides sent for review, the oldest first.
 */
export default function CityTours({ queue = false }) {
  const navigate = useNavigate();
  const admin = !isCreator();
  const [filter, setFilter] = useState('');
  const [query, setQuery] = useState('');
  const status = queue ? 'pending' : filter;
  const { data, loading, error, refetch } = useApi(`/admin/city-tours${status ? `?status=${status}` : ''}`);

  const tours = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (data || []).filter((t) => !q
      || [t.title, t.city, t.country, t.author_name].some((v) => (v || '').toLowerCase().includes(q)));
  }, [data, query]);

  const open = (id) => navigate(id ? `/city-tours/edit?id=${id}` : '/city-tours/edit');

  if (error && !data) return <PageError error={error} onRetry={refetch} />;

  return (
    <div>
      <div className="xp-toolbar">
        {queue ? (
          <div className="xp-section-hint" style={{ margin: 0 }}>
            Guides sent for review, the oldest first. Open one, check it in the phone preview, then put it live or send it back with a note.
          </div>
        ) : (
          <div className="seg">
            {FILTERS.map((f) => (
              <button key={f.key} type="button" className={`seg-btn ${filter === f.key ? 'active' : ''}`} onClick={() => setFilter(f.key)}>
                {f.label}
              </button>
            ))}
          </div>
        )}
        <div className="xp-toolbar-right">
          <SearchBar value={query} onChange={setQuery} placeholder="Search guides" />
          <button type="button" className="btn btn-ghost btn-sm" onClick={refetch} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
          {!queue && (
            <button type="button" className="btn btn-primary btn-sm" onClick={() => open(null)}>
              <PlusIcon size={14} /> New guide
            </button>
          )}
        </div>
      </div>

      {loading && !data ? <PageLoading /> : tours.length === 0 ? (
        <EmptyState icon={<RouteIcon size={28} />} title={queue ? 'Nothing waiting for review' : 'No guides here yet'}>
          {queue
            ? 'Guides that creators send for review show up here.'
            : 'Start one with “New guide”: the city, where the journey starts, then each ride and stop.'}
        </EmptyState>
      ) : (
        <div className="card ctg-list">
          {tours.map((t) => (
            <button key={t.id} type="button" className="ctg-row" onClick={() => open(t.id)}>
              <span className="ctg-thumb">
                {t.cover_url ? <img src={mediaUrl(t.cover_url)} alt="" /> : <RouteIcon size={18} />}
              </span>
              <span className="ctg-main">
                <strong>{t.title || 'Untitled guide'}</strong>
                <span>
                  {[[t.city, t.country].filter(Boolean).join(', '), `${t.stop_count} stop${t.stop_count === 1 ? '' : 's'}`,
                    admin ? `by ${t.author_name}` : ''].filter(Boolean).join(' · ')}
                </span>
                {t.review_status === 'changes_requested' && t.review_note && (
                  <span className="ctg-note">“{t.review_note}”</span>
                )}
              </span>
              <span className="ctg-badges">
                {tourBadges(t).map((b) => <Badge key={b.label} tone={b.tone}>{b.label}</Badge>)}
              </span>
              <span className="ctg-side">
                {queue ? `Sent ${formatDate(t.submitted_at)}` : `Saved ${formatDate(t.updated_at)}`}
                {admin && t.is_live && <span>{t.taps || 0} partner taps</span>}
                {admin && t.is_live && (
                  <span>{t.trips_started || 0} started · {t.trips_finished || 0} finished</span>
                )}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** The review queue: the same list, waiting guides only. */
export function CityTourQueue() {
  return <CityTours queue />;
}
