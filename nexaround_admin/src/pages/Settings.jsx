import React from 'react';

export default function Settings() {
  return (
    <div>
      <div className="card-header" style={{ marginBottom: '20px' }}>
        <div className="card-title">General Settings</div>
        <button className="btn btn-primary" onClick={() => alert('Saving settings...')}>
          Save Changes
        </button>
      </div>

      <div className="card" style={{ padding: '24px' }}>
        <div style={{ marginBottom: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Platform Configuration</h4>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Platform Name</label>
            <input type="text" className="form-input" defaultValue="NexARound" />
          </div>
          <div className="form-group">
            <label className="form-label">Contact Email</label>
            <input type="email" className="form-input" defaultValue="support@nexaround.com" />
          </div>
        </div>

        <div style={{ borderTop: '1px solid var(--border)', paddingTop: '24px' }}>
          <h4 style={{ marginBottom: '12px', color: 'var(--text-primary)' }}>Security & API</h4>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Google Maps API Key</label>
            <input type="password" className="form-input" defaultValue="************************" />
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Mapbox API Key</label>
            <input type="password" className="form-input" defaultValue="************************" />
          </div>
          <div className="form-group" style={{ marginBottom: '16px' }}>
            <label className="form-label">Gemini API Key</label>
            <input type="password" className="form-input" defaultValue="************************" />
          </div>
          <div className="form-group">
            <label className="form-label">Default Geofence Radius (meters)</label>
            <input type="number" className="form-input" defaultValue="100" />
          </div>
        </div>
      </div>
    </div>
  );
}
