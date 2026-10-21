import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useApi, apiPut } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import { RefreshIcon, StarIcon } from '../components/Icons';
import { EmptyState, ErrorBanner, Loader, Pagination, Tabs } from '../components/Lists';
import Stars from '../components/Stars';
import { formatDateTime } from '../format';
import { useToast } from '../toast';

const PAGE_SIZE = 25;
const MAX_REPLY = 1000;

/** One review, with the reply box under it. */
function ReviewCard({ review, onSaved }) {
  const notify = useToast();
  const [editing, setEditing] = useState(false);
  const [text, setText] = useState(review.vendor_reply || '');
  const [saving, setSaving] = useState(false);

  const save = async (reply) => {
    setSaving(true);
    try {
      const updated = await apiPut(`/partner/reviews/${review.id}/reply`, { reply });
      onSaved(updated);
      setEditing(false);
      setText(updated.vendor_reply || '');
      notify(reply ? 'Reply published' : 'Reply removed');
    } catch (err) {
      notify(`Could not save the reply: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="xp-section rv-card">
      <div className="rv-head">
        <div>
          <strong>{review.reviewer_name}</strong>{' '}
          <Stars value={review.rating} size={15} />
        </div>
        <div className="muted" title={formatDateTime(review.created_at)}>
          {review.package_title || 'Experience'} · {formatDateTime(review.created_at)}
          {review.edited_at && ' · edited'}
        </div>
      </div>

      {review.comment
        ? <div className="quote">{review.comment}</div>
        : <div className="muted">Rated without a comment.</div>}

      {!editing && review.vendor_reply && (
        <div className="rv-reply">
          <div className="dl-label">Your reply · {formatDateTime(review.vendor_replied_at)}</div>
          <div>{review.vendor_reply}</div>
          <div className="rv-actions">
            <button className="btn btn-ghost btn-sm" onClick={() => { setText(review.vendor_reply); setEditing(true); }}>Edit reply</button>
            <button
              className="btn btn-ghost btn-sm" disabled={saving}
              onClick={() => { if (confirm('Remove your reply?')) save(''); }}
            >
              Remove
            </button>
          </div>
        </div>
      )}

      {!editing && !review.vendor_reply && (
        <div className="rv-actions">
          <button className="btn btn-primary btn-sm" onClick={() => setEditing(true)}>Reply</button>
        </div>
      )}

      {editing && (
        <div className="rv-reply">
          <div className="dl-label">Your public reply</div>
          <textarea
            className="form-textarea" rows={4} value={text} maxLength={MAX_REPLY} autoFocus
            placeholder="Thank them, and answer anything they raised. Travellers see this under the review."
            onChange={(e) => setText(e.target.value)}
          />
          <div className="rv-actions">
            <span className="muted">{text.length}/{MAX_REPLY}</span>
            <button
              className="btn btn-ghost btn-sm" disabled={saving}
              onClick={() => { setEditing(false); setText(review.vendor_reply || ''); }}
            >
              Cancel
            </button>
            <button
              className="btn btn-primary btn-sm" disabled={saving || !text.trim()}
              onClick={() => save(text.trim())}
            >
              {saving ? 'Saving…' : 'Publish reply'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * Travellers' reviews of this vendor's packages, newest first, with a place to
 * answer each in public. Hidden reviews (taken down by NexAround) are not
 * listed. The tab and page live in the URL.
 */
export default function Reviews() {
  const [params, setParams] = useSearchParams();
  const unanswered = params.get('filter') === 'unanswered';
  const page = Math.max(1, Number(params.get('page')) || 1);

  const { data, error, refetch } = useApi(
    `/partner/reviews?page=${page}&page_size=${PAGE_SIZE}${unanswered ? '&unanswered=true' : ''}`
  );
  const [saved, setSaved] = useState({});

  // A new review arrives in the bell; the list follows.
  useLiveEvent(['activity.created', RESYNC], refetch);

  const reviews = (data?.reviews || []).map((r) => saved[r.id] || r);
  const totalPages = Math.max(1, Math.ceil((data?.total || 0) / PAGE_SIZE));

  const setQuery = (changes) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(changes)) {
      if (v) next.set(k, v); else next.delete(k);
    }
    setParams(next);
  };

  const tabs = [
    { value: '', label: 'All reviews', count: data ? data.review_count : null },
    { value: 'unanswered', label: 'Needs a reply', count: data ? data.unanswered : null },
  ];

  return (
    <>
      <div className="xp-toolbar">
        <Tabs
          items={tabs} value={unanswered ? 'unanswered' : ''}
          onChange={(value) => setQuery({ filter: value, page: '' })}
        />
        <div className="xp-toolbar-right">
          {data?.average != null && (
            <span className="rv-average" title="Average of all published reviews">
              <StarIcon size={16} className="rv-avg-star" />
              <strong>{Number(data.average).toFixed(1)}</strong>
              <span className="muted">({data.review_count} {data.review_count === 1 ? 'review' : 'reviews'})</span>
            </span>
          )}
          <button className="btn btn-ghost btn-sm" onClick={refetch} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      <ErrorBanner>{error}</ErrorBanner>
      {!data && !error && <Loader />}

      {data && reviews.length === 0 && (
        <EmptyState icon={StarIcon} title={unanswered ? 'Nothing waiting for a reply' : 'No reviews yet'} card>
          {unanswered
            ? 'Every review has an answer.'
            : 'Travellers can rate a package once you have confirmed their booking and the day has passed.'}
        </EmptyState>
      )}

      <div className="rv-list">
        {reviews.map((r) => (
          <ReviewCard
            key={r.id} review={r}
            onSaved={(updated) => {
              setSaved((s) => ({ ...s, [updated.id]: updated }));
              refetch();
            }}
          />
        ))}
      </div>

      <Pagination
        page={page} totalPages={totalPages}
        onPage={(p) => setQuery({ page: p > 1 ? String(p) : '' })}
      />
    </>
  );
}
