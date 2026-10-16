import { useState, useEffect } from 'react';
import { apiGet, apiPut } from '../api';
import { SecretField, PageLoading, Switch } from '../components/Kit';
import FxStatusCard from '../components/FxStatusCard';

// Travel-data providers feeding Odyssey plans (backend: app/services/providers).
const PROVIDER_FIELDS = {
  travelpayouts_api_token: '',
  travelpayouts_marker: '',
  travelpayouts_project_id: '',
  gettransfer_api_token: '',
  provider_mode_gettransfer: 'off',
  provider_mode_airalo: 'off',
  provider_mode_wegotrip: 'off',
  provider_mode_aviasales: 'off',
  provider_mode_klook: 'off',
  provider_mode_gocity: 'off',
  provider_mode_kiwi: 'off',
  provider_mode_atlas: 'off',
  atlas_key_id: '',
  atlas_signing_secret: '',
};

const PROVIDER_SWITCHES = [
  { key: 'provider_mode_gettransfer', name: 'GetTransfer', use: 'Airport & city-to-city transfer prices' },
  { key: 'provider_mode_airalo', name: 'Airalo', use: 'eSIM prices per country' },
  { key: 'provider_mode_wegotrip', name: 'WeGoTrip', use: 'Tour & ticket prices, ratings, photos' },
  { key: 'provider_mode_aviasales', name: 'Aviasales', use: 'Book on Aviasales link on flights (no prices)' },
  { key: 'provider_mode_klook', name: 'Klook', use: 'Things-to-do link for cities WeGoTrip has no tickets in' },
  { key: 'provider_mode_gocity', name: 'Go City', use: 'Sightseeing-pass link for big cities (2+ days)' },
  { key: 'provider_mode_kiwi', name: 'Kiwi.com', use: 'Second flight link beside Aviasales (no prices)' },
  { key: 'provider_mode_atlas', name: 'HelloSafe Atlas', use: 'Travel-insurance comparison & live prices on trips abroad' },
];

export default function Settings() {
  const [platformName, setPlatformName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [googleMapsApiKey, setGoogleMapsApiKey] = useState('');
  const [mapboxAccessToken, setMapboxAccessToken] = useState('');
  const [geminiApiKey, setGeminiApiKey] = useState('');
  const [geoapifyApiKey, setGeoapifyApiKey] = useState('');
  const [defaultGeofenceRadius, setDefaultGeofenceRadius] = useState('');
  const [unsplashApiKey, setUnsplashApiKey] = useState('');
  const [serpapiKey, setSerpapiKey] = useState('');
  const [providers, setProviders] = useState(PROVIDER_FIELDS);
  const [countryMode, setCountryMode] = useState(true);
  const [fxKey, setFxKey] = useState('');
  // Bumped after a save, so the currency card re-checks a new key at once.
  const [fxVersion, setFxVersion] = useState(0);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  // Loaded once on open; loading starts true, so nothing is set before the reply.
  useEffect(() => {
    apiGet('/admin/settings')
      .then((res) => {
        setPlatformName(res.platform_name || '');
        setContactEmail(res.contact_email || '');
        setGoogleMapsApiKey(res.google_maps_api_key || '');
        setMapboxAccessToken(res.mapbox_access_token || '');
        setGeminiApiKey(res.gemini_api_key || '');
        setGeoapifyApiKey(res.geoapify_api_key || '');
        setDefaultGeofenceRadius(res.default_geofence_radius || '100');
        setUnsplashApiKey(res.unsplash_api_key || '');
        setSerpapiKey(res.serpapi_key || '');
        setCountryMode(res.experiences_country_mode !== false);
        setFxKey(res.exchangerate_api_key || '');
        setProviders(Object.fromEntries(
          Object.entries(PROVIDER_FIELDS).map(([k, dflt]) => [k, res[k] || dflt])
        ));
      })
      .catch((err) => setError(err.message || 'Failed to load system settings.'))
      .finally(() => setLoading(false));
  }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    setSuccess(false);
    try {
      await apiPut('/admin/settings', {
        platform_name: platformName,
        contact_email: contactEmail,
        google_maps_api_key: googleMapsApiKey,
        mapbox_access_token: mapboxAccessToken,
        gemini_api_key: geminiApiKey,
        geoapify_api_key: geoapifyApiKey,
        default_geofence_radius: String(defaultGeofenceRadius),
        unsplash_api_key: unsplashApiKey,
        serpapi_key: serpapiKey,
        experiences_country_mode: countryMode,
        exchangerate_api_key: fxKey,
        ...providers,
      });
      setSuccess(true);
      setFxVersion((n) => n + 1);
      setTimeout(() => setSuccess(false), 3000);
    } catch (err) {
      setError(err.message || 'Failed to save system settings.');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <PageLoading />;
  }

  return (
    <form onSubmit={handleSave}>
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '20px' }}>
        <button type="submit" className="btn btn-primary" disabled={saving}>
          {saving ? 'Saving Changes...' : 'Save Changes'}
        </button>
      </div>

      {error && <div className="login-error" style={{ marginBottom: '20px' }}>{error}</div>}
      {success && <div className="badge badge-green" style={{ display: 'block', padding: '12px', marginBottom: '20px', textAlign: 'center', fontSize: '13px', fontWeight: 600 }}>System configurations updated successfully!</div>}

      <div className="card" style={{ padding: '24px' }}>
        <div style={{ marginBottom: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Platform Configuration</h4>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Platform Name</label>
            <input
              type="text"
              className="form-input"
              value={platformName}
              onChange={(e) => setPlatformName(e.target.value)}
              required
            />
          </div>
          <div className="form-group">
            <label className="form-label">Contact Email</label>
            <input
              type="email"
              className="form-input"
              value={contactEmail}
              onChange={(e) => setContactEmail(e.target.value)}
              required
            />
          </div>
        </div>

        <div style={{ borderTop: '1px solid var(--border)', paddingTop: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Security & API Proxies (Hidden on client)</h4>
          <p style={{ fontSize: '11px', color: 'var(--text-secondary)', marginBottom: '16px' }}>
            Keys entered below are stored safely in the database and never transmitted to client devices.
          </p>
          <SecretField
            label="Google Maps API Key"
            value={googleMapsApiKey}
            onChange={setGoogleMapsApiKey}
            placeholder="Google Maps Secret API Key"
            required
          />
          <SecretField
            label="Mapbox Access Token"
            value={mapboxAccessToken}
            onChange={setMapboxAccessToken}
            placeholder="Mapbox API Access Token"
            required
          />
          <SecretField
            label="Gemini API Key"
            value={geminiApiKey}
            onChange={setGeminiApiKey}
            placeholder="Google Gemini API Key"
            required
          />
          <SecretField
            label="SerpApi Key"
            tag="Live Google Flight & Hotel Search"
            value={serpapiKey}
            onChange={setSerpapiKey}
            placeholder="SerpApi Private Key (Google Flights & Hotels)"
          />
          <SecretField
            label="Unsplash API Key"
            tag="Destination Photos"
            value={unsplashApiKey}
            onChange={setUnsplashApiKey}
            placeholder="Unsplash API Access Key"
          />
          <SecretField
            label="Geoapify API Key"
            tag="Reverse Geocoding"
            value={geoapifyApiKey}
            onChange={setGeoapifyApiKey}
            placeholder="Geoapify API Key"
          />
          <div className="form-group">
            <label className="form-label">Default Geofence Radius (meters)</label>
            <input
              type="number"
              className="form-input"
              value={defaultGeofenceRadius}
              onChange={(e) => setDefaultGeofenceRadius(e.target.value)}
              required
            />
          </div>
        </div>

        <div style={{ borderTop: '1px solid var(--border)', paddingTop: '24px', marginTop: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Experiences</h4>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' }}>
            <div>
              <div style={{ fontWeight: 600, color: 'var(--text-primary)', fontSize: '13px' }}>Browse by country</div>
              <div style={{ fontSize: '11px', color: 'var(--text-secondary)', maxWidth: '520px' }}>
                On: the app lists Experiences by the country picked in its dropdown, with no distances,
                and includes vendors that have no map pin. Off: nearest first, which hides vendors with
                no map pin. Takes effect when you save.
              </div>
            </div>
            <Switch checked={countryMode} onChange={setCountryMode} />
          </div>
        </div>

        <div style={{ borderTop: '1px solid var(--border)', paddingTop: '24px', marginTop: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Currency Exchange Rates</h4>
          <p style={{ fontSize: '11px', color: 'var(--text-secondary)', marginBottom: '16px' }}>
            Converts experience prices into each traveller's currency in the app. Saving a new key fetches the rates with it straight away.
          </p>
          <SecretField
            label="ExchangeRate-API Key"
            tag="exchangerate-api.com · free plan, 1,500 requests a month"
            value={fxKey}
            onChange={setFxKey}
            placeholder="ExchangeRate-API dashboard → API key"
          />
          <FxStatusCard version={fxVersion} />
        </div>

        <div style={{ borderTop: '1px solid var(--border)', paddingTop: '24px', marginTop: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Travel Data Providers (Odyssey)</h4>
          <p style={{ fontSize: '11px', color: 'var(--text-secondary)', marginBottom: '16px' }}>
            Real prices for transfers, eSIMs, tours and backup flights. Changes reach plan generation within a minute.
          </p>
          <SecretField
            label="Travelpayouts API Token"
            tag="Aviasales flight data"
            value={providers.travelpayouts_api_token}
            onChange={(v) => setProviders({ ...providers, travelpayouts_api_token: v })}
            placeholder="Travelpayouts → Profile → API token"
          />
          <SecretField
            label="GetTransfer API Token"
            tag="Issued by Travelpayouts support"
            value={providers.gettransfer_api_token}
            onChange={(v) => setProviders({ ...providers, gettransfer_api_token: v })}
            placeholder="Request from support@travelpayouts.com"
          />
          <SecretField
            label="HelloSafe Atlas Key ID"
            tag="ak_test_... or ak_live_..."
            value={providers.atlas_key_id}
            onChange={(v) => setProviders({ ...providers, atlas_key_id: v })}
            placeholder="From HelloSafe Atlas → API keys"
          />
          <SecretField
            label="HelloSafe Atlas Signing Secret"
            tag="HMAC-SHA256 signature secret"
            value={providers.atlas_signing_secret}
            onChange={(v) => setProviders({ ...providers, atlas_signing_secret: v })}
            placeholder="Paste the secret HelloSafe showed when you created the key"
          />
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px', marginBottom: '16px' }}>
            <div className="form-group">
              <label className="form-label">Travelpayouts Partner ID (marker)</label>
              <input
                type="text"
                className="form-input"
                value={providers.travelpayouts_marker}
                onChange={(e) => setProviders({ ...providers, travelpayouts_marker: e.target.value })}
                placeholder="e.g. 781739"
                autoComplete="off"
              />
            </div>
            <div className="form-group">
              <label className="form-label">Travelpayouts Project ID (trs)</label>
              <input
                type="text"
                className="form-input"
                value={providers.travelpayouts_project_id}
                onChange={(e) => setProviders({ ...providers, travelpayouts_project_id: e.target.value })}
                placeholder="Travelpayouts → Profile → Sources"
                autoComplete="off"
              />
            </div>
          </div>
          <label className="form-label">Use in plans</label>
          <p style={{ fontSize: '11px', color: 'var(--text-secondary)', marginBottom: '12px' }}>
            Off: not called. Shadow: fetched and logged, not shown to travellers. Live: used in plans.
          </p>
          {PROVIDER_SWITCHES.map(({ key, name, use }) => (
            <div key={key} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px', padding: '10px 0', borderBottom: '1px solid var(--border)' }}>
              <div>
                <div style={{ fontWeight: 600, color: 'var(--text-primary)', fontSize: '13px' }}>{name}</div>
                <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>{use}</div>
              </div>
              <select
                className="form-input"
                style={{ width: '130px', flexShrink: 0 }}
                value={providers[key]}
                onChange={(e) => setProviders({ ...providers, [key]: e.target.value })}
              >
                <option value="off">Off</option>
                <option value="shadow">Shadow</option>
                <option value="live">Live</option>
              </select>
            </div>
          ))}
        </div>
      </div>
    </form>
  );
}
