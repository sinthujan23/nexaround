import React, { useState, useEffect } from 'react';
import { apiGet, apiPut } from '../api';

export default function Settings() {
  const [platformName, setPlatformName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [googleMapsApiKey, setGoogleMapsApiKey] = useState('');
  const [mapboxAccessToken, setMapboxAccessToken] = useState('');
  const [geminiApiKey, setGeminiApiKey] = useState('');
  const [defaultGeofenceRadius, setDefaultGeofenceRadius] = useState('');

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
      setDefaultGeofenceRadius(res.default_geofence_radius || '100');
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
        default_geofence_radius: String(defaultGeofenceRadius),
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
            <input
              type="password"
              className="form-input"
              value={googleMapsApiKey}
              onChange={(e) => setGoogleMapsApiKey(e.target.value)}
              placeholder="Google Maps Secret API Key"
              required
            />
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Mapbox Access Token</label>
            <input
              type="password"
              className="form-input"
              value={mapboxAccessToken}
              onChange={(e) => setMapboxAccessToken(e.target.value)}
              placeholder="Mapbox API Access Token"
              required
            />
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Gemini API Key</label>
            <input
              type="password"
              className="form-input"
              value={geminiApiKey}
              onChange={(e) => setGeminiApiKey(e.target.value)}
              placeholder="Google Gemini API Key"
              required
            />
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
