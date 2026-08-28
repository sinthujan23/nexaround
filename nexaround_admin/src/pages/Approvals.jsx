import { useState, useEffect, useRef, useMemo } from 'react';
import { useApi, apiPost, apiDelete, apiPut } from '../api';
import { CheckIcon, CrossIcon, MapPinIcon } from '../components/Icons';

export default function Approvals() {
  const { data, loading, error, refetch } = useApi('/admin/approvals');
  const categoriesRes = useApi('/categories');
  const categories = categoriesRes.data || [];

  const [selectedAttraction, setSelectedAttraction] = useState(null);
  const [editForm, setEditForm] = useState({
    name: '',
    category_id: '',
    address: '',
    latitude: 0,
    longitude: 0,
    description: '',
    history: '',
    entry_fee: 0,
    currency: 'USD'
  });

  const [isSubmitModalOpen, setIsSubmitModalOpen] = useState(false);
  const [submitForm, setSubmitForm] = useState({
    name: '',
    category_id: '',
    address: '',
    latitude: 0,
    longitude: 0,
    description: '',
    history: '',
    entry_fee: 0,
    currency: 'USD',
    is_active: false
  });

  const [isSaving, setIsSaving] = useState(false);

  const mapRef = useRef(null);
  const markersRef = useRef({});
  const selectedMarkerRef = useRef(null);

  const attractions = useMemo(() => data?.attractions || [], [data?.attractions]);
  const pendingCount = data?.total || 0;

  const handleSelectAttraction = (attraction) => {
    setSelectedAttraction(attraction);
    setEditForm({
      name: attraction.name || '',
      category_id: attraction.category_id || '',
      address: attraction.address || '',
      latitude: attraction.latitude,
      longitude: attraction.longitude,
      description: attraction.description || '',
      history: attraction.history || '',
      entry_fee: attraction.entry_fee || 0,
      currency: attraction.currency || 'USD'
    });

    if (mapRef.current) {
      mapRef.current.setView([attraction.latitude, attraction.longitude], 14);
    }
  };

  // Initialize and update Map markers
  useEffect(() => {
    if (!window.L) return;

    if (!mapRef.current) {
      // Create map container centered at a default location
      const map = window.L.map('approvals-map', {
        zoomControl: true
      }).setView([20.0, 0.0], 2);

      window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors'
      }).addTo(map);

      mapRef.current = map;
    }

    const map = mapRef.current;

    // Clear old markers
    Object.values(markersRef.current).forEach(marker => marker.remove());
    markersRef.current = {};
    selectedMarkerRef.current = null;

    const bounds = [];

    attractions.forEach(p => {
      const isSelected = selectedAttraction?.id === p.id;
      const marker = window.L.marker([p.latitude, p.longitude], {
        draggable: isSelected
      }).addTo(map);

      marker.bindTooltip(p.name, { permanent: false, direction: 'top' });

      marker.on('click', () => {
        handleSelectAttraction(p);
      });

      if (isSelected) {
        selectedMarkerRef.current = marker;

        marker.on('drag', (e) => {
          const latLng = e.target.getLatLng();
          setEditForm(prev => ({
            ...prev,
            latitude: Number(latLng.lat.toFixed(6)),
            longitude: Number(latLng.lng.toFixed(6))
          }));
        });

        marker.on('dragend', (e) => {
          const latLng = e.target.getLatLng();
          setEditForm(prev => ({
            ...prev,
            latitude: Number(latLng.lat.toFixed(6)),
            longitude: Number(latLng.lng.toFixed(6))
          }));
        });
      }

      markersRef.current[p.id] = marker;
      bounds.push([p.latitude, p.longitude]);
    });

    // Fit map bounds to show all markers if not editing a specific one
    if (bounds.length > 0 && !selectedAttraction) {
      map.fitBounds(bounds, { padding: [40, 40] });
    }
  }, [attractions, selectedAttraction]);

  // Synchronize marker position on map when coordinate inputs change manually
  useEffect(() => {
    if (selectedMarkerRef.current && editForm.latitude && editForm.longitude) {
      const currentPos = selectedMarkerRef.current.getLatLng();
      if (currentPos.lat !== editForm.latitude || currentPos.lng !== editForm.longitude) {
        selectedMarkerRef.current.setLatLng([editForm.latitude, editForm.longitude]);
        if (mapRef.current) {
          mapRef.current.panTo([editForm.latitude, editForm.longitude]);
        }
      }
    }
  }, [editForm.latitude, editForm.longitude]);


  const handleApprove = async () => {
    setIsSaving(true);
    try {
      // Update coordinates/details and set is_active: true
      await apiPut(`/admin/attractions/${selectedAttraction.id}`, {
        ...editForm,
        is_active: true
      });
      setSelectedAttraction(null);
      refetch();
      alert('Place approved and coordinates updated successfully!');
    } catch (err) {
      alert(`Approval failed: ${err.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  const handleQuickApprove = async (id, e) => {
    if (e) e.stopPropagation();
    try {
      await apiPost(`/admin/attractions/${id}/approve`);
      if (selectedAttraction?.id === id) {
        setSelectedAttraction(null);
      }
      refetch();
      alert('Place approved successfully.');
    } catch (err) {
      alert(`Approval failed: ${err.message}`);
    }
  };

  const handleSaveChanges = async (e) => {
    if (e) e.preventDefault();
    setIsSaving(true);
    try {
      await apiPut(`/admin/attractions/${selectedAttraction.id}`, {
        ...editForm,
        is_active: false
      });
      refetch();
      alert('Coordinates and details saved.');
    } catch (err) {
      alert(`Failed to save changes: ${err.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  const handleReject = async (id, e) => {
    if (e) e.stopPropagation();
    if (!confirm('Are you sure you want to reject and delete this place submission?')) return;
    setIsSaving(true);
    try {
      await apiDelete(`/admin/attractions/${id}/reject`);
      if (selectedAttraction?.id === id) {
        setSelectedAttraction(null);
      }
      refetch();
    } catch (err) {
      alert(`Rejection failed: ${err.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  const handleOpenSubmitModal = () => {
    let defaultLat = 0;
    let defaultLng = 0;
    if (mapRef.current) {
      const center = mapRef.current.getCenter();
      defaultLat = Number(center.lat.toFixed(6));
      defaultLng = Number(center.lng.toFixed(6));
    }
    setSubmitForm({
      name: '',
      category_id: categories[0]?.id || '',
      address: '',
      latitude: defaultLat,
      longitude: defaultLng,
      description: '',
      history: '',
      entry_fee: 0,
      currency: 'USD',
      is_active: false
    });
    setIsSubmitModalOpen(true);
  };

  const handleSubmitNewPlace = async (e) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await apiPost('/attractions/', submitForm);
      setIsSubmitModalOpen(false);
      refetch();
      alert('Place submitted successfully! It is now pending review.');
    } catch (err) {
      alert(`Failed to submit place: ${err.message}`);
    } finally {
      setIsSaving(false);
    }
  };

  if (error) {
    return (
      <div className="login-error" style={{ margin: '20px' }}>
        Failed to load place submissions: {error}
      </div>
    );
  }

  return (
    <div className="approvals-modern-container">
      {/* Premium Hero Banner (Compact) */}
      <div className="approvals-hero" style={{
        background: 'linear-gradient(135deg, var(--accent) 0%, var(--accent-2) 100%)',
        borderRadius: '16px',
        padding: '16px 24px',
        color: 'white',
        marginBottom: '16px',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        boxShadow: '0 8px 24px rgba(0, 122, 124, 0.12)'
      }}>
        <div>
          <h2 style={{ fontSize: '20px', fontWeight: 800, margin: 0, letterSpacing: '-0.5px' }}>Pending Review Queue</h2>
          <p style={{ margin: '4px 0 0 0', opacity: 0.9, fontSize: '13px', fontWeight: 500 }}>
            You have <strong style={{ color: '#fff', background: 'rgba(255,255,255,0.2)', padding: '2px 8px', borderRadius: '12px' }}>{pendingCount}</strong> places waiting for your review.
          </p>
        </div>
        <button className="btn" onClick={handleOpenSubmitModal} style={{ 
          background: 'white', 
          color: 'var(--accent)', 
          padding: '10px 20px', 
          borderRadius: '10px',
          fontWeight: 800,
          fontSize: '13px',
          boxShadow: '0 4px 14px rgba(0,0,0,0.1)'
        }}>
          + Submit New Place
        </button>
      </div>

      <div className="approvals-split">
        {/* Left Column: Submissions Modern List */}
        <div className="approvals-list-col">
          <div className="card modern-card" style={{ border: 'none', padding: '0', background: 'transparent', boxShadow: 'none' }}>
            <div className="modern-list-container">
              {loading && attractions.length === 0 ? (
                <div className="empty-state">
                  <div className="loader"></div>
                  <p>Retrieving submissions...</p>
                </div>
              ) : attractions.length === 0 ? (
                <div className="empty-state">
                  <div className="empty-icon">
                    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path>
                      <polyline points="22 4 12 14.01 9 11.01"></polyline>
                    </svg>
                  </div>
                  <h3 style={{ margin: '0 0 4px 0', fontSize: '16px', color: 'var(--text-primary)' }}>All caught up!</h3>
                  <p style={{ margin: 0, fontSize: '13px' }}>There are no pending place submissions to review.</p>
                </div>
              ) : (
                <div className="modern-list">
                  {attractions.map(p => {
                    const isSelected = selectedAttraction?.id === p.id;
                    const locText = p.address ? p.address : `Lat: ${p.latitude.toFixed(4)}, Lng: ${p.longitude.toFixed(4)}`;

                    return (
                      <div
                        key={p.id}
                        className={`modern-list-item ${isSelected ? 'selected' : ''}`}
                        onClick={() => handleSelectAttraction(p)}
                      >
                        <div className="list-item-main">
                          <div className="list-item-icon">
                            <MapPinIcon size={18} />
                          </div>
                          <div className="list-item-content">
                            <div className="list-item-title">{p.name}</div>
                            <div className="list-item-meta" style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                              <span className="badge badge-ghost" style={{ fontSize: '9px', padding: '2px 6px' }}>{p.category_name || 'General'}</span>
                              <span className="list-item-loc">{locText}</span>
                              {p.has_duplicate_coordinates && (
                                <span className="badge badge-red" style={{ fontSize: '9px', padding: '2px 6px', fontWeight: 'bold' }}>
                                  ⚠️ Duplicate Coordinates
                                </span>
                              )}
                            </div>
                          </div>
                        </div>
                        <div className="list-item-actions" onClick={e => e.stopPropagation()}>
                          <button className="action-icon-btn approve" onClick={(e) => handleQuickApprove(p.id, e)} title="Approve">
                            <CheckIcon size={14} />
                          </button>
                          <button className="action-icon-btn reject" onClick={(e) => handleReject(p.id, e)} title="Reject">
                            <CrossIcon size={14} />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Right Column: OSM Map and Detailed Coordinate Editor */}
        <div className="approvals-map-col">
          <div className="map-card">
            <div className="card-title" style={{ marginBottom: '8px', fontSize: '15px', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <MapPinIcon size={16} style={{ color: 'var(--accent)' }} />
              OSM Location Verification
            </div>
            <div id="approvals-map" className="map-container" style={{ overflow: 'hidden' }}></div>
            <div style={{ 
              fontSize: '11.5px', 
              color: 'var(--text-secondary)', 
              marginTop: '10px', 
              fontStyle: 'italic',
              position: 'relative',
              zIndex: 11,
              display: 'flex',
              alignItems: 'center',
              gap: '6px'
            }}>
              <span style={{ fontSize: '14px', lineHeight: 1 }}>{selectedAttraction ? "📍" : "ℹ️"}</span>
              <span>{selectedAttraction ? "Selected pin is draggable on map to refine coordinates." : "Select a submission from the list to enable location verification."}</span>
            </div>
          </div>

          {selectedAttraction && (
            <div className="card correction-panel" style={{ padding: '20px' }}>
              <div className="correction-title" style={{ marginBottom: '12px' }}>
                <MapPinIcon size={18} style={{ color: 'var(--accent)' }} />
                Verify & Correct Location
              </div>

              {selectedAttraction.has_duplicate_coordinates && (
                <div style={{
                  background: 'rgba(229,57,53,0.08)',
                  borderLeft: '4px solid var(--danger)',
                  padding: '12px 16px',
                  borderRadius: '8px',
                  marginBottom: '16px',
                  fontSize: '13px',
                  color: 'var(--danger)',
                  display: 'flex',
                  alignItems: 'flex-start',
                  gap: '8px',
                  fontWeight: 500,
                  lineHeight: '1.4'
                }}>
                  <span style={{ fontSize: '15px' }}>⚠️</span>
                  <span><strong>Warning:</strong> Another attraction in the database already exists with these exact coordinates. If approved, this will result in duplicate coordinates. Please review or adjust the coordinates.</span>
                </div>
              )}

              <form onSubmit={handleSaveChanges} className="correction-form">
                <div className="form-group">
                  <label className="form-label" style={{ fontSize: '12px' }}>Place Name</label>
                  <input
                    type="text"
                    className="form-input"
                    value={editForm.name}
                    onChange={e => setEditForm(prev => ({ ...prev, name: e.target.value }))}
                    required
                  />
                </div>

                <div className="form-grid-2">
                  <div className="form-group">
                    <label className="form-label" style={{ fontSize: '12px' }}>Category</label>
                    <select
                      className="form-input"
                      style={{ height: '38px', padding: '0 10px', background: 'var(--bg-card)', color: 'var(--text-primary)', border: '1px solid var(--border)', borderRadius: '8px' }}
                      value={editForm.category_id}
                      onChange={e => setEditForm(prev => ({ ...prev, category_id: e.target.value }))}
                    >
                      <option value="">General (No Category)</option>
                      {categories.map(cat => (
                        <option key={cat.id} value={cat.id}>{cat.name}</option>
                      ))}
                    </select>
                  </div>
                  <div className="form-group">
                    <label className="form-label" style={{ fontSize: '12px' }}>Entry Fee (USD)</label>
                    <input
                      type="number"
                      step="0.01"
                      className="form-input"
                      value={editForm.entry_fee}
                      onChange={e => setEditForm(prev => ({ ...prev, entry_fee: Number(e.target.value) }))}
                    />
                  </div>
                </div>

                <div className="form-group">
                  <label className="form-label" style={{ fontSize: '12px' }}>Street Address / Location Context</label>
                  <input
                    type="text"
                    className="form-input"
                    value={editForm.address}
                    onChange={e => setEditForm(prev => ({ ...prev, address: e.target.value }))}
                    placeholder="e.g. 123 Main Street"
                  />
                </div>

                <div className="form-grid-2">
                  <div className="form-group">
                    <label className="form-label" style={{ fontSize: '12px' }}>Latitude</label>
                    <input
                      type="number"
                      step="any"
                      className="form-input"
                      value={editForm.latitude}
                      onChange={e => setEditForm(prev => ({ ...prev, latitude: Number(e.target.value) }))}
                      required
                    />
                  </div>
                  <div className="form-group">
                    <label className="form-label" style={{ fontSize: '12px' }}>Longitude</label>
                    <input
                      type="number"
                      step="any"
                      className="form-input"
                      value={editForm.longitude}
                      onChange={e => setEditForm(prev => ({ ...prev, longitude: Number(e.target.value) }))}
                      required
                    />
                  </div>
                </div>

                <div style={{ display: 'flex', gap: '8px', marginTop: '14px' }}>
                  <button type="submit" className="btn btn-primary" style={{ flex: 1, padding: '10px', fontSize: '13px' }} disabled={isSaving}>
                    Save Corrections
                  </button>
                  <button
                    type="button"
                    className="action-btn approve"
                    onClick={handleApprove}
                    style={{ padding: '10px 16px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '4px' }}
                    disabled={isSaving}
                  >
                    <CheckIcon size={14} /> Approve & Activate
                  </button>
                  <button
                    type="button"
                    className="action-btn reject"
                    onClick={(e) => handleReject(selectedAttraction.id, e)}
                    style={{ padding: '10px 16px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '4px' }}
                    disabled={isSaving}
                  >
                    <CrossIcon size={14} /> Reject
                  </button>
                </div>
              </form>
            </div>
          )}
        </div>
      </div>

      {/* Submit New Place Modal */}
      {isSubmitModalOpen && (
        <div className="modal-overlay" onClick={() => setIsSubmitModalOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <h3 style={{ margin: 0, fontWeight: 700, fontSize: '18px', color: 'var(--text-primary)' }}>Submit New Place</h3>
              <button
                onClick={() => setIsSubmitModalOpen(false)}
                style={{ background: 'none', border: 'none', fontSize: '20px', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                &times;
              </button>
            </div>
            <form onSubmit={handleSubmitNewPlace}>
              <div className="form-group" style={{ marginBottom: '14px' }}>
                <label className="form-label">Place Name</label>
                <input
                  type="text"
                  className="form-input"
                  value={submitForm.name}
                  onChange={e => setSubmitForm(prev => ({ ...prev, name: e.target.value }))}
                  placeholder="e.g. Central Park Zoo"
                  required
                />
              </div>

              <div className="form-grid-2" style={{ marginBottom: '14px' }}>
                <div className="form-group">
                  <label className="form-label">Category</label>
                  <select
                    className="form-input"
                    style={{ height: '38px', padding: '0 10px', background: 'var(--bg-card)', color: 'var(--text-primary)', border: '1px solid var(--border)', borderRadius: '8px' }}
                    value={submitForm.category_id}
                    onChange={e => setSubmitForm(prev => ({ ...prev, category_id: e.target.value }))}
                  >
                    <option value="">General (No Category)</option>
                    {categories.map(cat => (
                      <option key={cat.id} value={cat.id}>{cat.name}</option>
                    ))}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Entry Fee (USD)</label>
                  <input
                    type="number"
                    step="0.01"
                    className="form-input"
                    value={submitForm.entry_fee}
                    onChange={e => setSubmitForm(prev => ({ ...prev, entry_fee: Number(e.target.value) }))}
                  />
                </div>
              </div>

              <div className="form-group" style={{ marginBottom: '14px' }}>
                <label className="form-label">Street Address / Location Details</label>
                <input
                  type="text"
                  className="form-input"
                  value={submitForm.address}
                  onChange={e => setSubmitForm(prev => ({ ...prev, address: e.target.value }))}
                  placeholder="e.g. 64th St & 5th Ave, New York"
                />
              </div>

              <div className="form-grid-2" style={{ marginBottom: '20px' }}>
                <div className="form-group">
                  <label className="form-label">Latitude</label>
                  <input
                    type="number"
                    step="any"
                    className="form-input"
                    value={submitForm.latitude}
                    onChange={e => setSubmitForm(prev => ({ ...prev, latitude: Number(e.target.value) }))}
                    required
                  />
                </div>
                <div className="form-group">
                  <label className="form-label">Longitude</label>
                  <input
                    type="number"
                    step="any"
                    className="form-input"
                    value={submitForm.longitude}
                    onChange={e => setSubmitForm(prev => ({ ...prev, longitude: Number(e.target.value) }))}
                    required
                  />
                </div>
              </div>

              <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end' }}>
                <button
                  type="button"
                  className="btn"
                  style={{ background: 'var(--border)', color: 'var(--text-secondary)' }}
                  onClick={() => setIsSubmitModalOpen(false)}
                >
                  Cancel
                </button>
                <button type="submit" className="btn btn-primary" disabled={isSaving}>
                  {isSaving ? 'Submitting...' : 'Submit Place'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
