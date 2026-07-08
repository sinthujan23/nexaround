import React, { useState, useEffect } from 'react';
import { apiGet, apiPut } from '../api';

const EyeIcon = ({ size = 20, ...props }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    {...props}
  >
    <path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0z" />
    <circle cx="12" cy="12" r="3" />
  </svg>
);

const EyeOffIcon = ({ size = 20, ...props }) => (
  <svg
    xmlns="http://www.w3.org/2000/svg"
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    strokeWidth="2"
    strokeLinecap="round"
    strokeLinejoin="round"
    {...props}
  >
    <path d="M9.88 9.88a3 3 0 1 0 4.24 4.24" />
    <path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68" />
    <path d="M6.61 6.61A13.52 13.52 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61" />
    <line x1="2" y1="2" x2="22" y2="22" />
  </svg>
);

export default function Settings() {
  const [platformName, setPlatformName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [googleMapsApiKey, setGoogleMapsApiKey] = useState('');
  const [mapboxAccessToken, setMapboxAccessToken] = useState('');
  const [geminiApiKey, setGeminiApiKey] = useState('');
  const [geoapifyApiKey, setGeoapifyApiKey] = useState('');
  const [defaultGeofenceRadius, setDefaultGeofenceRadius] = useState('');
  const [unsplashApiKey, setUnsplashApiKey] = useState('');

  const [showGoogleKey, setShowGoogleKey] = useState(false);
  const [showMapboxToken, setShowMapboxToken] = useState(false);
  const [showGeminiKey, setShowGeminiKey] = useState(false);
  const [showGeoapifyKey, setShowGeoapifyKey] = useState(false);
  const [showUnsplashKey, setShowUnsplashKey] = useState(false);

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    fetchSettings();
  }, []);

  const fetchSettings = async () => {
    setLoading(true);
    setError('');
    try {
      const res = await apiGet('/admin/settings');
      setPlatformName(res.platform_name || '');
      setContactEmail(res.contact_email || '');
      setGoogleMapsApiKey(res.google_maps_api_key || '');
      setMapboxAccessToken(res.mapbox_access_token || '');
      setGeminiApiKey(res.gemini_api_key || '');
      setGeoapifyApiKey(res.geoapify_api_key || '');
      setDefaultGeofenceRadius(res.default_geofence_radius || '100');
      setUnsplashApiKey(res.unsplash_api_key || '');
    } catch (err) {
      setError(err.message || 'Failed to load system settings.');
    } finally {
      setLoading(false);
    }
  };

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
      });
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
    } catch (err) {
      setError(err.message || 'Failed to save system settings.');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div style={{ textAlign: 'center', padding: '50px', color: 'var(--text-secondary)' }}>
        <span style={{ fontSize: '16px' }}>Fetching platform configurations...</span>
      </div>
    );
  }

  return (
    <form onSubmit={handleSave}>
      <div className="card-header" style={{ marginBottom: '20px' }}>
        <div className="card-title">General Settings</div>
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
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Google Maps API Key</label>
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
              <input
                type="text"
                className="form-input"
                value={googleMapsApiKey}
                onChange={(e) => setGoogleMapsApiKey(e.target.value)}
                placeholder="Google Maps Secret API Key"
                autoComplete="off"
                required
                style={{
                  paddingRight: '46px',
                  WebkitTextSecurity: showGoogleKey ? 'none' : 'disc',
                }}
              />
              <button
                type="button"
                onClick={() => setShowGoogleKey(!showGoogleKey)}
                style={{
                  position: 'absolute',
                  right: '12px',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  padding: '4px',
                }}
              >
                {showGoogleKey ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
              </button>
            </div>
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Mapbox Access Token</label>
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
              <input
                type="text"
                className="form-input"
                value={mapboxAccessToken}
                onChange={(e) => setMapboxAccessToken(e.target.value)}
                placeholder="Mapbox API Access Token"
                autoComplete="off"
                required
                style={{
                  paddingRight: '46px',
                  WebkitTextSecurity: showMapboxToken ? 'none' : 'disc',
                }}
              />
              <button
                type="button"
                onClick={() => setShowMapboxToken(!showMapboxToken)}
                style={{
                  position: 'absolute',
                  right: '12px',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  padding: '4px',
                }}
              >
                {showMapboxToken ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
              </button>
            </div>
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Gemini API Key</label>
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
              <input
                type="text"
                className="form-input"
                value={geminiApiKey}
                onChange={(e) => setGeminiApiKey(e.target.value)}
                placeholder="Google Gemini API Key"
                autoComplete="off"
                required
                style={{
                  paddingRight: '46px',
                  WebkitTextSecurity: showGeminiKey ? 'none' : 'disc',
                }}
              />
              <button
                type="button"
                onClick={() => setShowGeminiKey(!showGeminiKey)}
                style={{
                  position: 'absolute',
                  right: '12px',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  padding: '4px',
                }}
              >
                {showGeminiKey ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
              </button>
            </div>
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Unsplash API Key <span style={{ fontSize: '11px', color: 'var(--accent)', fontWeight: 700 }}>Destination Photos</span></label>
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
              <input
                type="text"
                className="form-input"
                value={unsplashApiKey}
                onChange={(e) => setUnsplashApiKey(e.target.value)}
                placeholder="Unsplash API Access Key"
                autoComplete="off"
                style={{
                  paddingRight: '46px',
                  WebkitTextSecurity: showUnsplashKey ? 'none' : 'disc',
                }}
              />
              <button
                type="button"
                onClick={() => setShowUnsplashKey(!showUnsplashKey)}
                style={{
                  position: 'absolute',
                  right: '12px',
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  color: 'var(--text-secondary)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  padding: '4px',
                }}
              >
                {showUnsplashKey ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
              </button>
            </div>
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Geoapify API Key <span style={{ fontSize: '11px', color: 'var(--accent)', fontWeight: 700 }}>Reverse Geocoding</span></label>
            <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
              <input
                type="text"
                className="form-input"
                value={geoapifyApiKey}
                onChange={(e) => setGeoapifyApiKey(e.target.value)}
                placeholder="Geoapify API Key"
                autoComplete="off"
                style={{
                  paddingRight: '46px',
                  WebkitTextSecurity: showGeoapifyKey ? 'none' : 'disc',
                }}
              />
              <button
                type="button"
                onClick={() => setShowGeoapifyKey(!showGeoapifyKey)}
                style={{
                  position: 'absolute', right: '12px', background: 'none',
                  border: 'none', cursor: 'pointer', color: 'var(--text-secondary)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '4px',
                }}
              >
                {showGeoapifyKey ? <EyeOffIcon size={18} /> : <EyeIcon size={18} />}
              </button>
            </div>
          </div>
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
      </div>
    </form>
  );
}
