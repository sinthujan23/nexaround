import { useEffect, useRef, useState } from 'react';
import { apiGet } from '../api';
import { SearchIcon, MapPinIcon } from './Icons';

/**
 * Position a vendor by Google location search, then confirm on the map.
 *
 * The search goes through the backend (`/admin/experiences/place-search`)
 * rather than the Google Places JS SDK: there is no browser-side Google key in
 * this panel and the project's standing rule is that provider keys never reach
 * a client. The draggable-marker binding is lifted from Approvals.jsx, which
 * already solved the same two-way marker <-> input problem.
 */
export default function LocationPicker({
  mapId,
  latitude,
  longitude,
  address,
  onPick,
  // As with ImageUploader: defaulted to the admin path, so admin call sites
  // need no edit at all.
  searchEndpoint = '/admin/experiences/place-search',
}) {
  const mapRef = useRef(null);
  const markerRef = useRef(null);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState('');

  const hasPoint = latitude !== '' && longitude !== '' &&
    latitude !== null && longitude !== null &&
    !Number.isNaN(Number(latitude)) && !Number.isNaN(Number(longitude));

  // Create the map once.
  useEffect(() => {
    if (!window.L) return;
    if (mapRef.current) return;

    const start = hasPoint ? [Number(latitude), Number(longitude)] : [7.8731, 80.7718];
    const map = window.L.map(mapId, { zoomControl: true })
      .setView(start, hasPoint ? 14 : 7);

    window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors',
    }).addTo(map);

    mapRef.current = map;

    // Clicking the map is the fastest way to place a vendor with no Google
    // result — a jetty or a beach launch point often has no listing at all.
    map.on('click', (e) => {
      onPick({
        latitude: Number(e.latlng.lat.toFixed(6)),
        longitude: Number(e.latlng.lng.toFixed(6)),
      });
    });

    // Leaflet measures the container on creation; inside a freshly opened
    // panel that measurement is zero and the tiles render grey until nudged.
    setTimeout(() => map.invalidateSize(), 120);

    return () => {
      map.remove();
      mapRef.current = null;
      markerRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapId]);

  // Keep the marker in step with the form values, whichever changed them.
  useEffect(() => {
    if (!window.L || !mapRef.current) return;

    if (!hasPoint) {
      if (markerRef.current) {
        markerRef.current.remove();
        markerRef.current = null;
      }
      return;
    }

    const position = [Number(latitude), Number(longitude)];

    if (!markerRef.current) {
      const marker = window.L.marker(position, { draggable: true })
        .addTo(mapRef.current);

      const write = (e) => {
        const latLng = e.target.getLatLng();
        onPick({
          latitude: Number(latLng.lat.toFixed(6)),
          longitude: Number(latLng.lng.toFixed(6)),
        });
      };
      marker.on('drag', write);
      marker.on('dragend', write);

      markerRef.current = marker;
      mapRef.current.setView(position, 15);
      return;
    }

    const current = markerRef.current.getLatLng();
    if (current.lat !== Number(latitude) || current.lng !== Number(longitude)) {
      markerRef.current.setLatLng(position);
      mapRef.current.panTo(position);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [latitude, longitude]);

  const runSearch = async (e) => {
    e.preventDefault();
    if (query.trim().length < 2) return;

    setSearching(true);
    setError('');
    try {
      const center = mapRef.current ? mapRef.current.getCenter() : { lat: 7.87, lng: 80.77 };
      const res = await apiGet(
        `${searchEndpoint}?query=${encodeURIComponent(query.trim())}` +
        `&lat=${center.lat.toFixed(6)}&lng=${center.lng.toFixed(6)}`
      );
      setResults(res.places || []);
      if (!res.places || res.places.length === 0) setError('No places matched that search.');
    } catch (err) {
      setError(err.message || 'Search failed.');
      setResults([]);
    } finally {
      setSearching(false);
    }
  };

  const choose = (place) => {
    if (place.latitude == null || place.longitude == null) return;
    onPick({
      latitude: Number(Number(place.latitude).toFixed(6)),
      longitude: Number(Number(place.longitude).toFixed(6)),
      address: place.address || '',
      google_place_id: place.place_id || '',
      name: place.name || '',
    });
    setResults([]);
    setQuery('');
  };

  return (
    <div>
      <div className="form-group">
        <label className="form-label">Find the vendor on Google</label>
        <div style={{ display: 'flex', gap: '8px' }}>
          <input
            type="text"
            className="form-input"
            placeholder="e.g. Blue Lagoon Tours, Trincomalee"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') runSearch(e); }}
          />
          <button
            type="button"
            className="btn btn-ghost"
            onClick={runSearch}
            disabled={searching || query.trim().length < 2}
            style={{ whiteSpace: 'nowrap' }}
          >
            <SearchIcon size={16} /> {searching ? 'Searching…' : 'Search'}
          </button>
        </div>
        {error && (
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '6px' }}>
            {error}
          </div>
        )}
      </div>

      {results.length > 0 && (
        <div className="modern-list" style={{ marginBottom: '16px', maxHeight: '220px', overflowY: 'auto' }}>
          {results.map((place) => (
            <div
              key={place.place_id || `${place.latitude},${place.longitude}`}
              className="modern-list-item"
              style={{ cursor: 'pointer' }}
              onClick={() => choose(place)}
            >
              <MapPinIcon size={16} className="icon" />
              <div style={{ marginLeft: '10px' }}>
                <div style={{ fontWeight: 600 }}>{place.name || 'Unnamed place'}</div>
                <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                  {place.address || '—'}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      <div
        id={mapId}
        className="map-container"
        style={{ height: '260px', borderRadius: '12px', marginBottom: '12px' }}
      />
      <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginBottom: '12px' }}>
        Pick a search result, click the map, or drag the pin to fine-tune.
      </div>

      <div className="form-grid-2">
        <div className="form-group">
          <label className="form-label">Latitude</label>
          <input
            type="number" step="any" required className="form-input"
            value={latitude}
            onChange={(e) => onPick({ latitude: e.target.value === '' ? '' : Number(e.target.value) })}
          />
        </div>
        <div className="form-group">
          <label className="form-label">Longitude</label>
          <input
            type="number" step="any" required className="form-input"
            value={longitude}
            onChange={(e) => onPick({ longitude: e.target.value === '' ? '' : Number(e.target.value) })}
          />
        </div>
      </div>

      <div className="form-group">
        <label className="form-label">Address</label>
        <input
          type="text" className="form-input"
          value={address || ''}
          onChange={(e) => onPick({ address: e.target.value })}
        />
      </div>
    </div>
  );
}
