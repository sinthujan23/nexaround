import { useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { apiPost, mediaUrl, useApi } from '../api';
import { Badge, EmptyState, Modal, PageError, PageLoading, SearchBar, Toast } from '../components/Kit';
import { MuseumIcon, PlusIcon, RefreshIcon } from '../components/Icons';
import { useToast } from '../hooks';
import { COUNTRIES } from '../constants/countries';
import { TOUR_LABELS, formatVisitors } from '../museums';

const FILTERS = [
  { key: '', label: 'All' },
  { key: 'live', label: 'In the app' },
  { key: 'hidden', label: 'Hidden' },
];

/** Red line under a field. */
function FieldError({ message }) {
  return message ? <div className="form-field-error" role="alert">{message}</div> : null;
}

const NEW_FIELDS = [
  ['name', 'museum-new-name', 'Add the museum’s name.'],
  ['city', 'museum-new-city', 'Add the city.'],
  ['country', 'museum-new-country', 'Add the country.'],
];

/**
 * Museums as the app lists them: by world rank, each with its photo, place,
 * visitors and the tours its guide has. New ones start hidden from the app.
 */
export default function Museums() {
  const navigate = useNavigate();
  const { data, loading, error, refetch } = useApi('/admin/museums');
  const [filter, setFilter] = useState('');
  const [query, setQuery] = useState('');
  const [adding, setAdding] = useState(null);
  const [saving, setSaving] = useState(false);
  const [toast, notify] = useToast(5000);

  const museums = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (data || [])
      .filter((m) => !filter || (filter === 'hidden' ? m.is_hidden : !m.is_hidden))
      .filter((m) => !q || [m.name, m.city, m.country].some((v) => (v || '').toLowerCase().includes(q)));
  }, [data, filter, query]);

  const addErrors = adding?.checked
    ? Object.fromEntries(NEW_FIELDS.filter(([key]) => !adding[key].trim()).map(([key, , msg]) => [key, msg]))
    : {};

  const create = async () => {
    const missing = NEW_FIELDS.find(([key]) => !adding[key].trim());
    if (missing) {
      setAdding({ ...adding, checked: true });
      document.getElementById(missing[1])?.focus();
      return;
    }
    setSaving(true);
    try {
      const made = await apiPost('/admin/museums', {
        name: adding.name.trim(), city: adding.city.trim(), country: adding.country.trim(),
      });
      navigate(`/museums/edit?id=${made.id}`);
    } catch (err) {
      notify(err.message || 'Could not add the museum.', 'error');
      setSaving(false);
    }
  };

  if (error && !data) return <PageError error={error} onRetry={refetch} />;

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {FILTERS.map((f) => (
            <button key={f.key} type="button" className={`seg-btn ${filter === f.key ? 'active' : ''}`} onClick={() => setFilter(f.key)}>
              {f.label}
            </button>
          ))}
        </div>
        <div className="xp-toolbar-right">
          <SearchBar value={query} onChange={setQuery} placeholder="Search museums" />
          <button type="button" className="btn btn-ghost btn-sm" onClick={refetch} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
          <button type="button" className="btn btn-primary btn-sm" onClick={() => setAdding({ name: '', city: '', country: '' })}>
            <PlusIcon size={14} /> Add museum
          </button>
        </div>
      </div>

      {loading && !data ? <PageLoading /> : museums.length === 0 ? (
        <EmptyState icon={<MuseumIcon size={28} />} title="No museums here">
          {query || filter ? 'Nothing matches. Try another search or filter.' : 'Add one with “Add museum”.'}
        </EmptyState>
      ) : (
        <div className="card ctg-list">
          {museums.map((m) => (
            <button key={m.id} type="button" className="ctg-row" onClick={() => navigate(`/museums/edit?id=${m.id}`)}>
              <span className="ctg-thumb">
                {m.image_url ? <img src={mediaUrl(m.image_url)} alt="" loading="lazy" /> : <MuseumIcon size={18} />}
              </span>
              <span className="ctg-main">
                <strong>{m.rank ? `${m.rank}. ` : ''}{m.name}</strong>
                <span>
                  {[`${m.city}, ${m.country}`, formatVisitors(m.annual_visitors),
                    m.item_count ? `${m.item_count} must-see item${m.item_count === 1 ? '' : 's'}` : 'No items yet',
                  ].filter(Boolean).join(' · ')}
                </span>
              </span>
              <span className="ctg-badges">
                {m.tours.map((d) => <Badge key={d} tone="ghost">{TOUR_LABELS[d]}</Badge>)}
                <Badge tone={m.is_hidden ? 'yellow' : 'green'}>{m.is_hidden ? 'Hidden' : 'In the app'}</Badge>
              </span>
            </button>
          ))}
        </div>
      )}

      {adding && (
        <Modal title="Add a museum" onClose={() => setAdding(null)} maxWidth="480px">
          <div className="form-group">
            <label className="form-label" htmlFor="museum-new-name">Museum name *</label>
            <input
              id="museum-new-name" className="form-input" maxLength={255} value={adding.name}
              placeholder="e.g. Rijksmuseum" aria-invalid={!!addErrors.name || undefined}
              onChange={(e) => setAdding({ ...adding, name: e.target.value })}
            />
            <FieldError message={addErrors.name} />
          </div>
          <div className="form-grid-2">
            <div className="form-group">
              <label className="form-label" htmlFor="museum-new-city">City *</label>
              <input
                id="museum-new-city" className="form-input" maxLength={120} value={adding.city}
                placeholder="e.g. Amsterdam" aria-invalid={!!addErrors.city || undefined}
                onChange={(e) => setAdding({ ...adding, city: e.target.value })}
              />
              <FieldError message={addErrors.city} />
            </div>
            <div className="form-group">
              <label className="form-label" htmlFor="museum-new-country">Country *</label>
              <input
                id="museum-new-country" className="form-input" maxLength={120} value={adding.country}
                list="museum-countries" placeholder="e.g. Netherlands" aria-invalid={!!addErrors.country || undefined}
                onChange={(e) => setAdding({ ...adding, country: e.target.value })}
              />
              <FieldError message={addErrors.country} />
            </div>
          </div>
          <datalist id="museum-countries">
            {COUNTRIES.map((c) => <option key={c.code} value={c.name} />)}
          </datalist>
          <div className="xp-section-hint" style={{ margin: '0 0 16px' }}>
            It stays hidden from the app while you add its photo and must-see items. Switch it on when it is ready.
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setAdding(null)}>Cancel</button>
            <button type="button" className="btn btn-primary btn-sm" onClick={create} disabled={saving}>
              {saving ? 'Adding…' : 'Add and continue'}
            </button>
          </div>
        </Modal>
      )}
      <Toast toast={toast} />
    </div>
  );
}
