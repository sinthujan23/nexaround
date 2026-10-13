import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { useApi } from '../api';
import { CheckIcon, ClipboardCheckIcon, CrossIcon } from '../components/Icons';
import { Badge, Loading, PageError, Toast } from '../components/Kit';
import PlaceForm from '../components/PlaceForm';
import PlaceThumb from '../components/PlaceThumb';
import PlaceStatusDialog from '../components/PlaceStatusDialog';
import { useToast } from '../hooks';
import {
  SOURCE_LABELS, STATUS_DOT, STATUS_LABELS, formToBody, formatDate, formsDiffer, getPlace,
  listPlaces, nearbyPlaces, notifyPlacesChanged, placeToForm, reasonText, setPlaceStatus,
  updatePlace, usePlaceCounts, usePlacesChanged,
} from '../places';

const PAGE_SIZE = 50;

// Map dot colours for places around the one being reviewed.
const NEARBY_COLOR = { live: '#007a7c', pending: '#f59e0b', hidden: '#9aa1ad', rejected: '#e53935' };

const KINDS = [
  ['all', 'All'],
  ['user', 'From app users'],
  ['legacy', 'Old copies'],
];

/** Where a place in the queue came from, in one line. */
function originLine(place) {
  if (place.source === 'user') {
    const who = place.submitter ? place.submitter.display_name : 'an app user';
    return `Suggested by ${who} · ${formatDate(place.created_at)}`;
  }
  if (place.status_reason === 'legacy_inactive') {
    return `Old switched-off copy · added ${formatDate(place.created_at)}`;
  }
  return `${reasonText(place.status_reason) || SOURCE_LABELS[place.source]} · added ${formatDate(place.created_at)}`;
}

function ReviewDetail({ placeId, categories, position, total, onDone, onSkip, onBack, notify }) {
  const [place, setPlace] = useState(null);
  const [nearby, setNearby] = useState([]);
  const [form, setForm] = useState(placeToForm(null));
  const [initial, setInitial] = useState(form);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [rejecting, setRejecting] = useState(false);

  // Keyed by place id by the parent, so each place starts from empty state.
  useEffect(() => {
    let active = true;
    Promise.all([getPlace(placeId), nearbyPlaces(placeId).catch(() => [])])
      .then(([p, near]) => {
        if (!active) return;
        setPlace(p);
        setForm(placeToForm(p));
        setInitial(placeToForm(p));
        setNearby(near);
      })
      .catch((err) => { if (active) setError(err.message); });
    return () => { active = false; };
  }, [placeId]);

  const markers = useMemo(() => nearby.map((n) => ({
    id: n.id, latitude: n.latitude, longitude: n.longitude,
    name: `${n.name} (${STATUS_LABELS[n.status]})`, color: NEARBY_COLOR[n.status],
  })), [nearby]);

  if (error) return <div className="xp-empty"><strong>Could not load this place</strong>{error}</div>;
  if (!place) return <Loading>Loading place…</Loading>;

  const dirty = formsDiffer(form, initial);
  const liveTwins = nearby.filter((n) => n.status === 'live');

  const decide = async (fn, message) => {
    setBusy(true);
    try {
      await fn();
      notifyPlacesChanged();
      notify(message);
      onDone();
    } catch (err) {
      notify(err.message, 'error');
      setBusy(false);
    }
  };

  const approve = () => decide(async () => {
    if (dirty) await updatePlace(placeId, formToBody(form));
    await setPlaceStatus(placeId, 'live');
  }, `"${form.name}" approved. It is live in the app.`);

  const sameAs = (twin) => decide(
    () => setPlaceStatus(placeId, 'rejected', 'duplicate_location', `Same place as "${twin.name}"`),
    `Rejected as a duplicate of "${twin.name}".`,
  );

  return (
    <>
      <div className="xp-detail-head">
        <div style={{ flex: 1, minWidth: 0 }}>
          <button className="xp-back" onClick={onBack}>← Queue</button>
          <div className="xp-detail-title">{place.name}</div>
          <div className="xp-detail-sub">{originLine(place)}</div>
        </div>
        <Badge tone="yellow">{position} of {total.toLocaleString()}</Badge>
      </div>

      <div className="xp-body">
        {place.submitter && (
          <div className="contact-card" style={{ marginBottom: '16px' }}>
            <div className="contact-card-lines">
              {place.submitter.display_name}<br />
              <span>{place.submitter.email}</span>
            </div>
          </div>
        )}

        <div className="xp-section">
          <div className="xp-section-title">Already in the database nearby</div>
          <div className="xp-section-hint">
            {nearby.length === 0
              ? 'Nothing within 150 m. This looks like a new place.'
              : 'If one of these is the same place, reject this one as a duplicate.'}
          </div>
          {nearby.length > 0 && (
            <div className="modern-list" style={{ maxHeight: '240px', overflowY: 'auto' }}>
              {nearby.map((n) => (
                <div key={n.id} className="modern-list-item" style={{ cursor: 'default' }}>
                  <PlaceThumb url={n.photo_urls?.[0]} size="32px" />
                  <div className="list-item-content" style={{ flex: 1, minWidth: 0, marginLeft: '10px' }}>
                    <div className="xp-row-title">{n.name}</div>
                    <div className="xp-row-sub">
                      <span className={`dot ${STATUS_DOT[n.status]}`} style={{ marginRight: '6px' }} />
                      {STATUS_LABELS[n.status]} · {Math.round(n.distance_m)} m away
                    </div>
                  </div>
                  {n.status === 'live' && (
                    <button className="btn btn-ghost btn-sm" disabled={busy} onClick={() => sameAs(n)}>
                      Same place
                    </button>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        <PlaceForm
          key={placeId}
          value={form}
          onChange={setForm}
          categories={categories}
          mapId={`review-map-${placeId}`}
          nearbyMarkers={markers}
        />
      </div>

      <div className="xp-savebar">
        <span>
          {dirty ? <span className="unsaved"><span className="dot dot-new" /> Your edits are saved when you approve</span>
            : liveTwins.length ? `${liveTwins.length} live place${liveTwins.length > 1 ? 's' : ''} nearby` : 'Check the pin, then decide.'}
        </span>
        <span style={{ display: 'flex', gap: '8px' }}>
          <button className="btn btn-ghost btn-sm" disabled={busy} onClick={onSkip}>Skip</button>
          <button className="btn btn-danger-ghost btn-sm" disabled={busy} onClick={() => setRejecting(true)}>
            <CrossIcon size={14} /> Reject
          </button>
          <button className="btn btn-primary btn-sm" disabled={busy} onClick={approve}>
            <CheckIcon size={14} /> {dirty ? 'Save & approve' : 'Approve'}
          </button>
        </span>
      </div>

      {rejecting && (
        <PlaceStatusDialog
          title={`Reject "${place.name}"`}
          intro="It stays out of the app, and Google won't be able to add it back."
          confirmLabel="Reject place"
          defaultReason={liveTwins.length ? 'duplicate_location' : ''}
          onConfirm={async (reason, note) => {
            await setPlaceStatus(placeId, 'rejected', reason, note);
            setRejecting(false);
            notifyPlacesChanged();
            notify(`"${place.name}" rejected.`);
            onDone();
          }}
          onClose={() => setRejecting(false)}
        />
      )}
    </>
  );
}

export default function ReviewQueue() {
  const [params, setParams] = useSearchParams();
  const [kind, setKind] = useState('all');
  const [page, setPage] = useState(1);
  const [selectedId, setSelectedId] = useState(params.get('id'));
  // Off after "← Queue" on a narrow screen, so the list stays in view.
  const [autoOpen, setAutoOpen] = useState(true);
  const [toast, notify] = useToast();
  const counts = usePlaceCounts();

  const filter = kind === 'user' ? { source: 'user' } : kind === 'legacy' ? { reason: 'legacy_inactive' } : {};
  const { data, loading, error, refetch } = useApi(listPlaces({
    status: 'pending', sort: 'queue', page, page_size: PAGE_SIZE, ...filter,
  }));
  const categoriesRes = useApi('/categories/');
  const categories = useMemo(
    () => [...(categoriesRes.data || [])].sort((a, b) => a.name.localeCompare(b.name)),
    [categoriesRes.data],
  );

  usePlacesChanged(refetch);

  const items = useMemo(() => data?.items || [], [data]);
  const total = data?.total || 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  // The open place: the one picked (or linked with ?id=) while it is still in
  // the queue, otherwise the first in the list.
  const picked = selectedId && (items.some((p) => p.id === selectedId) || selectedId === params.get('id'))
    ? selectedId : null;
  const currentId = picked || (autoOpen && data ? items[0]?.id || null : null);

  const index = items.findIndex((p) => p.id === currentId);
  const position = (page - 1) * PAGE_SIZE + (index >= 0 ? index + 1 : 1);

  const select = (id) => {
    setAutoOpen(true);
    setSelectedId(id);
    if (params.get('id')) setParams({}, { replace: true });
  };

  // After a decision the place leaves the queue: open the one after it.
  const next = () => {
    const after = items[index + 1] || items[index - 1];
    select(after && after.id !== currentId ? after.id : null);
    refetch();
  };

  const skip = () => {
    const after = items[index + 1];
    if (after) select(after.id);
    else if (page < pages) { setPage(page + 1); select(null); }
  };

  const changeKind = (k) => { setKind(k); setPage(1); select(null); };

  if (error && !data) return <PageError>Could not load the Review queue: {error}</PageError>;

  const kindCount = { all: counts?.pending, user: counts?.pending_user };

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {KINDS.map(([k, label]) => (
            <button key={k} className={`seg-btn ${kind === k ? 'active' : ''}`} onClick={() => changeKind(k)}>
              {label}
              {kindCount[k] != null && <span className="seg-count">{kindCount[k].toLocaleString()}</span>}
            </button>
          ))}
        </div>
        <div style={{ fontSize: '12.5px', color: 'var(--text-secondary)' }}>
          Approve to show a place in the app. Reject to keep it out for good.
          {' '}<Link to="/places" style={{ color: 'var(--accent)', fontWeight: 700 }}>All places →</Link>
        </div>
      </div>

      <div className={`xp-split ${currentId ? 'has-selection' : ''}`}>
        <div className="xp-pane xp-list-pane">
          <div className="xp-list-head">
            <span>{total.toLocaleString()} waiting</span>
            <span>App suggestions first, then oldest</span>
          </div>
          <div className="xp-list-body" style={{ opacity: loading ? 0.5 : 1 }}>
            {loading && !data && <Loading>Loading queue…</Loading>}
            {data && items.length === 0 && (
              <div className="xp-empty">
                <ClipboardCheckIcon size={28} />
                <strong>All caught up</strong>
                Nothing is waiting for review.
              </div>
            )}
            {items.map((p) => (
              <button
                key={p.id}
                className={`xp-row ${p.id === currentId ? 'active' : ''}`}
                onClick={() => select(p.id)}
              >
                <span className={`dot ${p.source === 'user' ? 'dot-new' : 'dot-hidden'}`} />
                <div className="xp-row-main">
                  <div className={`xp-row-title ${p.source === 'user' ? 'strong' : ''}`}>{p.name}</div>
                  <div className="xp-row-sub">{p.address || p.category_name || '—'}</div>
                </div>
                <div className="xp-row-side">
                  {p.source === 'user' ? <Badge tone="yellow">App user</Badge> : <span>Old copy</span>}
                  {p.has_duplicate_coordinates && <span>Same spot</span>}
                </div>
              </button>
            ))}
          </div>
          <div className="xp-list-foot">
            <span>Page {page} of {pages.toLocaleString()}</span>
            <span style={{ display: 'flex', gap: '6px' }}>
              <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => { setPage(page - 1); select(null); }}>Previous</button>
              <button className="btn btn-ghost btn-sm" disabled={page >= pages} onClick={() => { setPage(page + 1); select(null); }}>Next</button>
            </span>
          </div>
        </div>

        <div className="xp-pane xp-detail-pane">
          {currentId ? (
            <ReviewDetail
              key={currentId}
              placeId={currentId}
              categories={categories}
              position={position}
              total={total}
              onDone={next}
              onSkip={skip}
              onBack={() => { select(null); setAutoOpen(false); }}
              notify={notify}
            />
          ) : (
            <div className="xp-empty">
              <ClipboardCheckIcon size={28} />
              <strong>{total ? 'Pick a place to review' : 'All caught up'}</strong>
              {total ? 'Choose one from the list.' : 'Nothing is waiting for review.'}
            </div>
          )}
        </div>
      </div>

      <Toast toast={toast} />
    </div>
  );
}
