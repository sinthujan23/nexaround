import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useApi } from '../api';
import {
  MapPinIcon, PlusIcon, EditIcon, EyeOffIcon, EyeIcon, RefreshIcon, AlertTriangleIcon,
} from '../components/Icons';
import { Badge, Drawer, EmptyState, Loading, PageError, SearchBar, Switch, Toast } from '../components/Kit';
import PlaceForm from '../components/PlaceForm';
import PlaceThumb from '../components/PlaceThumb';
import PlaceStatusDialog from '../components/PlaceStatusDialog';
import { useToast } from '../hooks';
import {
  SOURCE_LABELS, STATUS_DOT, STATUS_LABELS, createPlace, deletePlace, escapeHtml,
  formToBody, formatDate, formatDateTime, formsDiffer, getPlace, listPlaces,
  notifyPlacesChanged, placeToForm, reasonText, setPlaceStatus, updatePlace,
  usePlaceCounts, usePlacesChanged,
} from '../places';

const PAGE_SIZE = 50;
const TABS = ['live', 'hidden', 'rejected'];
const TAB_HINTS = {
  live: 'Shown in the app.',
  hidden: 'Taken out of the app by an admin. Make one live again at any time.',
  rejected: "Suggestions that were turned down. They stay here so Google can't add them back.",
};

export function StatusLabel({ status }) {
  return (
    <span className="status-label">
      <span className={`dot ${STATUS_DOT[status] || ''}`} /> {STATUS_LABELS[status] || status}
    </span>
  );
}

/** Leaflet map of the current page's places. */
function PlacesMap({ places, focusId, onSelect }) {
  const mapRef = useRef(null);
  const markersRef = useRef({});

  useEffect(() => {
    if (!window.L) return;
    if (!mapRef.current) {
      const map = window.L.map('places-map', { zoomControl: true }).setView([7.8731, 80.7718], 7);
      window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors',
      }).addTo(map);
      mapRef.current = map;
    }
    const map = mapRef.current;
    Object.values(markersRef.current).forEach((m) => m.remove());
    markersRef.current = {};
    const bounds = [];
    places.forEach((p) => {
      const marker = window.L.marker([p.latitude, p.longitude]).addTo(map);
      marker.bindPopup(
        `<strong>${escapeHtml(p.name)}</strong><br/><span style="font-size:11px;color:#5a6070">`
        + `${escapeHtml(p.address || p.category_name || '')}</span>`,
      );
      marker.on('click', () => onSelect(p));
      markersRef.current[p.id] = marker;
      bounds.push([p.latitude, p.longitude]);
    });
    if (bounds.length) map.fitBounds(bounds, { padding: [30, 30], maxZoom: 14 });
  }, [places, onSelect]);

  useEffect(() => {
    const marker = focusId && markersRef.current[focusId];
    if (marker && mapRef.current) {
      mapRef.current.setView(marker.getLatLng(), 15);
      marker.openPopup();
    }
  }, [focusId]);

  useEffect(() => () => {
    if (mapRef.current) { mapRef.current.remove(); mapRef.current = null; }
  }, []);

  return <div id="places-map" className="map-container" style={{ height: '520px' }} />;
}

/** "Possible duplicate" places returned with a 409 or a save warning. */
function DuplicateWarning({ matches, children }) {
  return (
    <div className="contact-card" style={{ borderColor: 'rgba(245,158,11,0.4)', background: 'rgba(255,179,0,0.06)', marginBottom: '16px' }}>
      <div className="contact-card-lines" style={{ flex: 1 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
          <AlertTriangleIcon size={16} style={{ color: 'var(--warning)' }} />
          A similar place is already in the database
        </div>
        {matches.map((m) => (
          <div key={m.id}><span>{m.name} · {STATUS_LABELS[m.status] || m.status} · {Math.round(m.distance_m)} m away</span></div>
        ))}
      </div>
      {children}
    </div>
  );
}

/** Create a place, or edit one and change its status. */
function PlaceDrawer({ placeId, categories, onClose, onChanged, notify }) {
  const creating = !placeId;
  const [place, setPlace] = useState(null);
  const [form, setForm] = useState(() => placeToForm(null));
  const [initial, setInitial] = useState(form);
  const [loadError, setLoadError] = useState('');
  const [saving, setSaving] = useState(false);
  const [duplicates, setDuplicates] = useState(null);
  const [dialog, setDialog] = useState(null);

  useEffect(() => {
    if (creating) return;
    let active = true;
    getPlace(placeId)
      .then((p) => {
        if (!active) return;
        setPlace(p);
        setForm(placeToForm(p));
        setInitial(placeToForm(p));
      })
      .catch((err) => { if (active) setLoadError(err.message); });
    return () => { active = false; };
  }, [placeId, creating]);

  const dirty = formsDiffer(form, initial);

  const close = () => {
    if (dirty && !confirm('Discard your changes?')) return;
    onClose();
  };

  const save = async (e, confirmDuplicate = false) => {
    if (e) e.preventDefault();
    setSaving(true);
    try {
      if (creating) {
        await createPlace({ ...formToBody(form), confirm_duplicate: confirmDuplicate });
        notify('Place added. It is live in the app.');
        onChanged();
        onClose();
        return;
      }
      const res = await updatePlace(placeId, formToBody(form));
      setPlace((p) => ({ ...p, ...res.place }));
      setInitial(form);
      setDuplicates(res.warnings?.[0]?.matches || null);
      notify(res.warnings?.length ? 'Saved. Check the warning below.' : 'Saved.');
      onChanged();
    } catch (err) {
      if (err.status === 409 && err.detail?.code === 'possible_duplicate') {
        setDuplicates(err.detail.matches);
      } else {
        notify(`Could not save: ${err.message}`, 'error');
      }
    } finally {
      setSaving(false);
    }
  };

  const changeStatus = async (status, reason, note) => {
    const updated = await setPlaceStatus(placeId, status, reason, note);
    setPlace((p) => ({ ...p, ...updated }));
    setDialog(null);
    notifyPlacesChanged();
    onChanged();
    notify(
      status === 'live' ? 'The place is live in the app.'
        : status === 'hidden' ? 'Hidden from the app.'
          : status === 'pending' ? 'Sent back to the Review queue.' : 'Updated.',
    );
  };

  const run = (fn) => fn().catch((err) => notify(err.message, 'error'));

  const remove = async () => {
    if (!confirm(`Delete "${place.name}" for good? If it came from Google it may be added again later — hiding is usually better.`)) return;
    try {
      await deletePlace(placeId);
      notifyPlacesChanged();
      onChanged();
      notify('Place deleted.');
      onClose();
    } catch (err) {
      notify(err.message, 'error');
    }
  };

  const status = place?.status;
  const usage = place?.usage;
  const hasContent = usage && (usage.reviews > 0 || usage.media > 0);

  const statusActions = !creating && place && (
    <div className="drawer-foot-actions">
      {status === 'live' && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => setDialog('hide')}>
          <EyeOffIcon size={14} /> Hide from app
        </button>
      )}
      {status === 'hidden' && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => run(() => changeStatus('live'))}>
          <EyeIcon size={14} /> Make live again
        </button>
      )}
      {status === 'rejected' && (
        <>
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => run(() => changeStatus('live'))}>
            <EyeIcon size={14} /> Restore (make live)
          </button>
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => run(() => changeStatus('pending'))}>
            Back to Review queue
          </button>
        </>
      )}
      {status === 'pending' && (
        <Link className="btn btn-ghost btn-sm" to={`/places/review?id=${placeId}`}>Open in Review queue</Link>
      )}
    </div>
  );

  return (
    <>
      <Drawer
        title={creating ? 'Add place' : (place?.name || 'Place')}
        subtitle={creating ? 'Added places are live in the app straight away.' : place && (
          <StatusLabel status={place.status} />
        )}
        onClose={close}
        onSubmit={(e) => save(e)}
        footer={(
          <>
            {statusActions || <span />}
            <div className="drawer-foot-actions">
              <button type="button" className="btn btn-ghost" onClick={close}>Close</button>
              <button type="submit" className="btn btn-primary" disabled={saving || (!creating && !dirty)}>
                {saving ? 'Saving…' : creating ? 'Add place' : 'Save changes'}
              </button>
            </div>
          </>
        )}
      >
        {loadError && <PageError>{loadError}</PageError>}
        {!creating && !place && !loadError && <Loading>Loading place…</Loading>}

        {duplicates && duplicates.length > 0 && (
          <DuplicateWarning matches={duplicates}>
            {creating && (
              <button type="button" className="btn btn-ghost btn-sm" disabled={saving} onClick={() => save(null, true)}>
                Add anyway
              </button>
            )}
          </DuplicateWarning>
        )}

        {place && (
          <div className="xp-section">
            <dl className="dl-grid">
              <div><dt>Status</dt><dd><StatusLabel status={place.status} /></dd></div>
              <div><dt>Source</dt><dd>{SOURCE_LABELS[place.source] || place.source}</dd></div>
              {place.status_reason && (
                <div><dt>Reason</dt><dd>{reasonText(place.status_reason)}</dd></div>
              )}
              {place.reviewed_at && (
                <div><dt>Last decision</dt><dd>{place.reviewed_by} · {formatDateTime(place.reviewed_at)}</dd></div>
              )}
              {place.submitter && (
                <div><dt>Suggested by</dt><dd>{place.submitter.display_name} <span style={{ color: 'var(--text-secondary)', fontWeight: 500 }}>({place.submitter.email})</span></dd></div>
              )}
              <div><dt>Added</dt><dd className="muted">{formatDate(place.created_at)}</dd></div>
              <div><dt>People's activity</dt><dd className="muted">{usage.reviews} reviews · {usage.media} photos · {usage.visits} visits</dd></div>
              {place.google_place_id && (
                <div><dt>Google rating</dt><dd className="muted">{place.rating ? `${place.rating} (${place.review_count})` : '—'}</dd></div>
              )}
            </dl>
            {place.status_note && <div className="quote" style={{ marginTop: '14px' }}>{place.status_note}</div>}
          </div>
        )}

        {(creating || place) && (
          <PlaceForm
            value={form}
            onChange={setForm}
            categories={categories}
            mapId={`place-drawer-map-${placeId || 'new'}`}
          />
        )}

        {place && (
          <div className="xp-danger">
            <span>
              {hasContent
                ? 'People have added reviews or photos here, so it can only be hidden, not deleted.'
                : 'Delete only places added by mistake. To take a place out of the app, hide it.'}
            </span>
            <button type="button" className="btn btn-danger-ghost btn-sm" disabled={hasContent} onClick={remove}>
              Delete
            </button>
          </div>
        )}
      </Drawer>

      {dialog === 'hide' && (
        <PlaceStatusDialog
          title="Hide from app"
          intro="The place stays in the database and can be made live again at any time."
          confirmLabel="Hide place"
          onConfirm={(reason, note) => changeStatus('hidden', reason, note)}
          onClose={() => setDialog(null)}
        />
      )}
    </>
  );
}

export default function Places() {
  const [tab, setTab] = useState('live');
  const [searchVal, setSearchVal] = useState('');
  const [search, setSearch] = useState('');
  const [source, setSource] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [onlyDuplicates, setOnlyDuplicates] = useState(false);
  const [sort, setSort] = useState('newest');
  const [page, setPage] = useState(1);
  const [focusId, setFocusId] = useState(null);
  const [drawer, setDrawer] = useState(null); // { id } to edit, {} to create
  const [hiding, setHiding] = useState(null);
  const [toast, notify] = useToast();
  const counts = usePlaceCounts();

  useEffect(() => {
    const t = setTimeout(() => { setSearch(searchVal.trim()); setPage(1); }, 400);
    return () => clearTimeout(t);
  }, [searchVal]);

  const { data, loading, error, refetch } = useApi(listPlaces({
    status: tab, q: search, source, category_id: categoryId,
    possible_duplicate: onlyDuplicates, sort, page, page_size: PAGE_SIZE,
  }));
  const categoriesRes = useApi('/categories/');
  const categories = useMemo(
    () => [...(categoriesRes.data || [])].sort((a, b) => a.name.localeCompare(b.name)),
    [categoriesRes.data],
  );

  usePlacesChanged(refetch);

  const places = useMemo(() => data?.items || [], [data]);
  const total = data?.total || 0;
  const tabCounts = data?.counts || {};
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const filtered = search || source || categoryId || onlyDuplicates;

  const select = useCallback((p) => setFocusId(p.id), []);

  const changeTab = (t) => { setTab(t); setPage(1); setFocusId(null); };
  const setFilter = (setter) => (v) => { setter(v); setPage(1); };

  const quickStatus = async (p, status, reason) => {
    try {
      await setPlaceStatus(p.id, status, reason);
      notifyPlacesChanged();
      notify(status === 'live' ? `"${p.name}" is live in the app.` : `"${p.name}" hidden from the app.`);
    } catch (err) {
      notify(err.message, 'error');
    }
  };

  if (error && !data) return <PageError>Could not load places: {error}</PageError>;

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {TABS.map((t) => (
            <button key={t} className={`seg-btn ${tab === t ? 'active' : ''}`} onClick={() => changeTab(t)}>
              <span className={`dot ${STATUS_DOT[t]}`} /> {STATUS_LABELS[t]}
              <span className="seg-count">{(tabCounts[t] ?? 0).toLocaleString()}</span>
            </button>
          ))}
        </div>
        <div className="xp-toolbar-right">
          {counts?.pending > 0 && (
            <Link to="/places/review" className="btn btn-ghost btn-sm">
              <span className="dot dot-new" /> {counts.pending.toLocaleString()} waiting in Review queue
            </Link>
          )}
          <button className="btn btn-primary btn-sm" onClick={() => setDrawer({})}>
            <PlusIcon size={14} /> Add place
          </button>
        </div>
      </div>

      <div className="xp-toolbar">
        <div className="xp-toolbar-right">
          <SearchBar value={searchVal} onChange={setSearchVal} placeholder="Search name or address…" />
          <select className="xp-select" value={source} onChange={(e) => setFilter(setSource)(e.target.value)}>
            <option value="">All sources</option>
            {Object.entries(SOURCE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          <select className="xp-select" value={categoryId} onChange={(e) => setFilter(setCategoryId)(e.target.value)}>
            <option value="">All categories</option>
            {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <select className="xp-select" value={sort} onChange={(e) => setFilter(setSort)(e.target.value)}>
            <option value="newest">Newest first</option>
            <option value="oldest">Oldest first</option>
            <option value="updated">Recently changed</option>
            <option value="name">Name A–Z</option>
          </select>
          <Switch checked={onlyDuplicates} onChange={setFilter(setOnlyDuplicates)} label="Same spot as another place" />
        </div>
        <button className="icon-btn" title="Refresh" onClick={refetch}><RefreshIcon size={16} /></button>
      </div>

      <div style={{ fontSize: '12.5px', color: 'var(--text-secondary)', margin: '-4px 0 12px' }}>
        {TAB_HINTS[tab]}
      </div>

      <div className="approvals-split places-split">
        <div className="card" style={{ padding: 0, minWidth: 0 }}>
          {loading && !data ? (
            <Loading>Loading places…</Loading>
          ) : places.length === 0 ? (
            <EmptyState icon={<MapPinIcon size={28} />} title={filtered ? 'No places match' : `No ${STATUS_LABELS[tab].toLowerCase()} places`}>
              {filtered ? 'Try a different search or filter.' : TAB_HINTS[tab]}
            </EmptyState>
          ) : (
            <div className="table-wrap">
              <table className="places-table">
                <thead>
                  <tr>
                    <th>Place</th>
                    <th>Source</th>
                    <th>{tab === 'live' ? 'Added' : 'Reason'}</th>
                    <th aria-label="Actions" />
                  </tr>
                </thead>
                <tbody style={{ opacity: loading ? 0.5 : 1 }}>
                  {places.map((p) => (
                    <tr
                      key={p.id}
                      className={`clickable-row ${focusId === p.id ? 'selected' : ''}`}
                      onClick={() => select(p)}
                    >
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', minWidth: 0 }}>
                          <PlaceThumb url={p.photo_urls?.[0]} />
                          <div style={{ minWidth: 0 }}>
                            <div className="xp-row-title" style={{ maxWidth: '240px' }}>{p.name}</div>
                            <div className="xp-row-sub" style={{ maxWidth: '240px' }}>
                              {[p.category_name, p.address].filter(Boolean).join(' · ') || '—'}
                            </div>
                          </div>
                          {p.has_duplicate_coordinates && (
                            <Badge tone="yellow" style={{ padding: '1px 8px', whiteSpace: 'nowrap' }} title="Another place sits at exactly the same spot">Same spot</Badge>
                          )}
                        </div>
                      </td>
                      <td><Badge tone="ghost" style={{ whiteSpace: 'nowrap' }}>{SOURCE_LABELS[p.source] || p.source}</Badge></td>
                      <td style={{ fontSize: '12.5px', color: 'var(--text-secondary)', whiteSpace: 'nowrap' }}>
                        {tab === 'live' ? formatDate(p.created_at) : reasonText(p.status_reason) || '—'}
                      </td>
                      <td onClick={(e) => e.stopPropagation()} style={{ whiteSpace: 'nowrap', textAlign: 'right' }}>
                        <button className="icon-btn" title="Edit" onClick={() => setDrawer({ id: p.id })}><EditIcon size={15} /></button>
                        {tab === 'live' && (
                          <button className="icon-btn" title="Hide from app" onClick={() => setHiding(p)}><EyeOffIcon size={15} /></button>
                        )}
                        {tab !== 'live' && (
                          <button className="icon-btn" title="Make live" onClick={() => quickStatus(p, 'live')}><EyeIcon size={15} /></button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <div className="xp-list-foot">
            <span>
              {total ? `${((page - 1) * PAGE_SIZE + 1).toLocaleString()}–${Math.min(page * PAGE_SIZE, total).toLocaleString()} of ${total.toLocaleString()}` : '0 places'}
            </span>
            <span style={{ display: 'flex', gap: '6px' }}>
              <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</button>
              <button className="btn btn-ghost btn-sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</button>
            </span>
          </div>
        </div>

        <div className="approvals-map-col">
          <div className="map-card">
            <PlacesMap places={places} focusId={focusId} onSelect={select} />
          </div>
        </div>
      </div>

      {drawer && (
        <PlaceDrawer
          placeId={drawer.id}
          categories={categories}
          onClose={() => setDrawer(null)}
          onChanged={refetch}
          notify={notify}
        />
      )}

      {hiding && (
        <PlaceStatusDialog
          title={`Hide "${hiding.name}"`}
          intro="The place stays in the database and can be made live again at any time."
          confirmLabel="Hide place"
          onConfirm={async (reason, note) => {
            await setPlaceStatus(hiding.id, 'hidden', reason, note);
            setHiding(null);
            notifyPlacesChanged();
            notify(`"${hiding.name}" hidden from the app.`);
          }}
          onClose={() => setHiding(null)}
        />
      )}

      <Toast toast={toast} />
    </div>
  );
}
