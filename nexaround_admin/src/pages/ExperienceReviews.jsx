import { useEffect, useState } from 'react';
import { useApi, apiGet, apiPatch } from '../api';
import { RefreshIcon, StarIcon } from '../components/Icons';
import { SearchBar, Toast } from '../components/Kit';
import { useToast } from '../hooks';

const PAGE_SIZE = 25;
const STATUSES = ['published', 'hidden'];
const STATUS_LABELS = { published: 'Published', hidden: 'Hidden' };
const TZ = 'Asia/Colombo';

const formatDateTime = (value) =>
  value
    ? new Date(value).toLocaleString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
    })
    : '—';

const formatAge = (value) => {
  const minutes = Math.floor((Date.now() - new Date(value).getTime()) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.floor(minutes / 60)}h`;
  if (minutes < 60 * 24 * 7) return `${Math.floor(minutes / 1440)}d`;
  return new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: TZ });
};

export function Stars({ value, size = 14 }) {
  return (
    <span className="rv-stars" title={`${value} out of 5`} aria-label={`${value} out of 5`}>
      {[1, 2, 3, 4, 5].map((n) => (
        <StarIcon key={n} size={size} className={n <= value ? 'on' : 'off'} />
      ))}
    </span>
  );
}

export default function ExperienceReviews() {
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState(null);
  const [saving, setSaving] = useState(false);
  const [counts, setCounts] = useState({});
  const [countsVersion, setCountsVersion] = useState(0);
  const [toast, notify] = useToast();

  const { data, error, refetch } = useApi(
    `/admin/experiences/reviews?page=${page}&page_size=${PAGE_SIZE}`
    + (statusFilter ? `&status=${statusFilter}` : '')
  );

  const raw = data?.reviews || [];
  const total = data?.total || 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  useEffect(() => {
    let active = true;
    Promise.all(
      ['', ...STATUSES].map((s) =>
        apiGet(`/admin/experiences/reviews?page=1&page_size=1${s ? `&status=${s}` : ''}`)
          .then((res) => [s || 'all', res.total])
          .catch(() => [s || 'all', null])
      )
    ).then((pairs) => { if (active) setCounts(Object.fromEntries(pairs)); });
    return () => { active = false; };
  }, [countsVersion]);

  const refresh = () => {
    refetch();
    setCountsVersion((n) => n + 1);
  };

  const q = search.trim().toLowerCase();
  const reviews = raw.filter((r) =>
    !q || [r.reviewer_name, r.package_title, r.vendor_name, r.comment, r.vendor_reply]
      .some((f) => (f || '').toLowerCase().includes(q))
  );

  const changeFilter = (status) => {
    setStatusFilter(status);
    setPage(1);
    setSelected(null);
  };

  const update = async (patch, message) => {
    setSaving(true);
    try {
      const updated = await apiPatch(`/admin/experiences/reviews/${selected.id}`, patch);
      setSelected(updated);
      refresh();
      notify(message);
    } catch (err) {
      notify(`Could not update the review: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const filters = [['', 'All'], ...STATUSES.map((s) => [s, STATUS_LABELS[s]])];

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {filters.map(([value, label]) => (
            <button
              key={value || 'all'}
              className={`seg-btn ${statusFilter === value ? 'active' : ''}`}
              onClick={() => changeFilter(value)}
            >
              {value && <span className={`dot dot-${value === 'published' ? 'live' : 'hidden'}`} />}
              {label}
              {counts[value || 'all'] != null && <span className="seg-count">{counts[value || 'all']}</span>}
            </button>
          ))}
        </div>

        <div className="xp-toolbar-right">
          <SearchBar value={search} onChange={setSearch} placeholder="Search reviewer, package, text…" />
          <button className="btn btn-ghost btn-sm" onClick={refresh} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      <div className={`xp-split ${selected ? 'has-selection' : ''}`}>
        <aside className="xp-pane xp-list-pane">
          <div className="xp-list-body">
            {!data && <div className="loader" />}

            {data && reviews.length === 0 && (
              <div className="xp-empty">
                <StarIcon size={32} />
                <strong>{search || statusFilter ? 'Nothing matches' : 'No reviews yet'}</strong>
                {search || statusFilter
                  ? 'Try another filter or search.'
                  : 'Travellers can rate an experience once the provider has confirmed their booking and the day has passed.'}
              </div>
            )}

            {reviews.map((r) => (
              <button
                key={r.id}
                className={`xp-row ${selected?.id === r.id ? 'active' : ''}`}
                onClick={() => setSelected(r)}
                style={{ alignItems: 'flex-start' }}
              >
                <span className={`dot dot-${r.status === 'published' ? 'live' : 'hidden'}`} style={{ marginTop: 6 }} title={STATUS_LABELS[r.status]} />
                <div className="xp-row-main">
                  <div className="xp-row-title">
                    {r.reviewer_name} <Stars value={r.rating} size={12} />
                  </div>
                  <div className="xp-row-sub" style={{ color: 'var(--text-primary)' }}>{r.package_title || 'Experience'}</div>
                  <div className="xp-row-sub rv-clip">{r.comment || 'No comment'}</div>
                </div>
                <div className="xp-row-side" title={formatDateTime(r.created_at)}>{formatAge(r.created_at)}</div>
              </button>
            ))}
          </div>

          {totalPages > 1 && (
            <div className="xp-list-foot">
              <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</button>
              <span>Page {page} of {totalPages}</span>
              <button className="btn btn-ghost btn-sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</button>
            </div>
          )}
        </aside>

        <section className="xp-pane xp-detail-pane">
          {!selected && (
            <div className="xp-empty">
              <StarIcon size={36} />
              <strong>Select a review</strong>
              Hide one that breaks the rules; it leaves the app and every average at once.
            </div>
          )}

          {selected && (
            <>
              <div className="xp-detail-head">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <button className="xp-back" onClick={() => setSelected(null)}>← All reviews</button>
                  <div className="xp-detail-title">{selected.reviewer_name} <Stars value={selected.rating} size={16} /></div>
                  <div className="xp-detail-sub">
                    Posted {formatDateTime(selected.created_at)}
                    {selected.edited_at && ` · edited ${formatDateTime(selected.edited_at)}`}
                  </div>
                </div>
                <span className="status-label">
                  <span className={`dot dot-${selected.status === 'published' ? 'live' : 'hidden'}`} /> {STATUS_LABELS[selected.status] || selected.status}
                </span>
              </div>

              <div className="xp-body">
                <div className="xp-section">
                  <dl className="dl-grid">
                    <div><dt>Experience</dt><dd>{selected.package_title || '—'}</dd></div>
                    <div><dt>Provider</dt><dd>{selected.vendor_name || '—'}</dd></div>
                  </dl>
                  <div style={{ marginTop: 18 }}>
                    <div className="dl-label">Review</div>
                    {selected.comment
                      ? <div className="quote">{selected.comment}</div>
                      : <div className="muted">The traveller left a rating without a comment.</div>}
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Provider’s reply</div>
                  {selected.vendor_reply ? (
                    <>
                      <div className="xp-section-hint">Replied {formatDateTime(selected.vendor_replied_at)}. Public.</div>
                      <div className="quote">{selected.vendor_reply}</div>
                      <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 10 }}>
                        <button
                          className="btn btn-ghost btn-sm" disabled={saving}
                          onClick={() => {
                            if (confirm('Take the provider’s reply down? They can write another.')) {
                              update({ clear_reply: true }, 'Reply removed');
                            }
                          }}
                        >
                          Remove reply
                        </button>
                      </div>
                    </>
                  ) : (
                    <div className="muted">No reply yet.</div>
                  )}
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Moderation</div>
                  <div className="xp-section-hint">
                    {selected.status === 'published'
                      ? 'Published in the app. Hiding removes it from the list and from every average; the traveller still sees their own review marked hidden.'
                      : `Hidden${selected.hidden_at ? ` since ${formatDateTime(selected.hidden_at)}` : ''}. Restoring puts it back in the app and in the averages.`}
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
                    {selected.status === 'published' ? (
                      <button
                        className="btn btn-danger-ghost btn-sm" disabled={saving}
                        onClick={() => {
                          if (confirm('Hide this review from the app?')) update({ status: 'hidden' }, 'Review hidden');
                        }}
                      >
                        {saving ? 'Saving…' : 'Hide review'}
                      </button>
                    ) : (
                      <button
                        className="btn btn-primary btn-sm" disabled={saving}
                        onClick={() => update({ status: 'published' }, 'Review restored')}
                      >
                        {saving ? 'Saving…' : 'Restore review'}
                      </button>
                    )}
                  </div>
                </div>
              </div>
            </>
          )}
        </section>
      </div>

      <Toast toast={toast} />
    </div>
  );
}
