import LocationPicker from './LocationPicker';
import ImageUploader from './ImageUploader';

/**
 * Name, category, location, description and photos of one place. Used by the
 * All places drawer and the Review queue, so both edit a place the same way.
 */
export default function PlaceForm({ value, onChange, categories, mapId, nearbyMarkers }) {
  const set = (patch) => onChange({ ...value, ...patch });

  // A Google search result fills the name too, but never overwrites one the
  // admin already typed.
  const onPick = (picked) => {
    const patch = {};
    ['latitude', 'longitude', 'address'].forEach((k) => {
      if (k in picked) patch[k] = picked[k];
    });
    if (picked.name && !value.name.trim()) patch.name = picked.name;
    set(patch);
  };

  // A fragment, not a wrapper: the sections must be siblings of the caller's
  // own .xp-section blocks for the divider rule (.xp-section + .xp-section).
  return (
    <>
      <div className="xp-section">
        <div className="form-grid-2">
          <div className="form-group">
            <label className="form-label">Name</label>
            <input
              className="form-input" required maxLength={255}
              value={value.name} onChange={(e) => set({ name: e.target.value })}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Category</label>
            <select
              className="form-select"
              value={value.category_id || ''}
              onChange={(e) => set({ category_id: e.target.value })}
            >
              <option value="">No category</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>
        </div>
      </div>

      <div className="xp-section">
        <div className="xp-section-title">Location</div>
        <div className="xp-section-hint">
          Drag the pin to the exact spot.
          {nearbyMarkers?.length ? ' Grey dots are other places already in the database.' : ''}
        </div>
        <LocationPicker
          mapId={mapId}
          latitude={value.latitude}
          longitude={value.longitude}
          address={value.address}
          onPick={onPick}
          searchLabel="Find the place on Google"
          searchPlaceholder="e.g. Sigiriya Rock Fortress"
          extraMarkers={nearbyMarkers}
        />
      </div>

      <div className="xp-section">
        <div className="xp-section-title">About</div>
        <div className="form-group">
          <label className="form-label">Description</label>
          <textarea
            className="form-textarea" rows={3}
            value={value.description} onChange={(e) => set({ description: e.target.value })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">History</label>
          <textarea
            className="form-textarea" rows={3}
            value={value.history} onChange={(e) => set({ history: e.target.value })}
          />
        </div>
        <div className="form-grid-2">
          <div className="form-group">
            <label className="form-label">Entry fee</label>
            <input
              type="number" min="0" step="any" className="form-input"
              value={value.entry_fee} onChange={(e) => set({ entry_fee: e.target.value })}
            />
          </div>
          <div className="form-group">
            <label className="form-label">Currency</label>
            <input
              className="form-input" maxLength={10}
              value={value.currency} onChange={(e) => set({ currency: e.target.value })}
            />
          </div>
        </div>
      </div>

      <div className="xp-section">
        <ImageUploader
          label="Photos"
          value={value.photo_urls}
          onChange={(photo_urls) => set({ photo_urls })}
        />
      </div>
    </>
  );
}
