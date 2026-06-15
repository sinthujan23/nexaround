import React, { useState, useEffect, useRef } from 'react';
import { MapPinIcon, PlusIcon, EditIcon, TrashIcon, CrossIcon } from '../components/Icons';
import { useApi, apiPost, apiPut, apiDelete } from '../api';

export default function Attractions() {
  const [searchVal, setSearchVal] = useState('');
  const [searchQuery, setSearchQuery] = useState('');

  // Debounce search input changes
  useEffect(() => {
    const handler = setTimeout(() => {
      setSearchQuery(searchVal);
    }, 400);
    return () => clearTimeout(handler);
  }, [searchVal]);

  const { data, loading, error, refetch } = useApi(
    `/admin/attractions?search=${encodeURIComponent(searchQuery)}`
  );

  const categoriesRes = useApi('/categories');
  const categories = categoriesRes.data || [];

  const attractions = data?.attractions || [];
  const totalCount = data?.total || 0;

  const [selectedAttraction, setSelectedAttraction] = useState(null);

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [formData, setFormData] = useState({
    name: '', category: 'Landmark', location: '', lat: '', lng: '', status: 'Active', image: '', entry_fee: '0.0'
  });

  const mapRef = useRef(null);
  const markersRef = useRef({});

  // Initialize and update Map markers
  useEffect(() => {
    if (!window.L) return;

    if (!mapRef.current) {
      // Create map container centered at a default location
      const map = window.L.map('attractions-map', {
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

    const bounds = [];

    attractions.forEach(p => {
      const marker = window.L.marker([p.latitude, p.longitude]).addTo(map);

      marker.bindPopup(`
        <div style="font-family: sans-serif; padding: 2px; min-width: 150px;">
          <h4 style="margin: 0 0 4px 0; font-weight: 700; color: #007a7c;">${p.name}</h4>
          <p style="margin: 0 0 6px 0; font-size: 11px; color: #5a6070;">${p.address || 'No address'}</p>
          <span style="font-size: 9px; background: rgba(0, 122, 124, 0.06); color: #007a7c; padding: 2px 6px; border-radius: 4px; font-weight: 600;">${p.category_name || 'General'}</span>
        </div>
      `);

      marker.on('click', () => {
        setSelectedAttraction(p);
      });

      markersRef.current[p.id] = marker;
      bounds.push([p.latitude, p.longitude]);
    });

    // Fit map bounds to show all markers if not focusing on a specific selected attraction
    if (bounds.length > 0 && !selectedAttraction) {
      map.fitBounds(bounds, { padding: [40, 40], maxZoom: 14 });
    }
  }, [attractions, selectedAttraction]);

  const handleSelectAttraction = (p) => {
    setSelectedAttraction(p);
    if (mapRef.current) {
      mapRef.current.setView([p.latitude, p.longitude], 15);
      const marker = markersRef.current[p.id];
      if (marker) {
        marker.openPopup();
      }
    }
  };

  const openAddModal = () => {
    setEditingId(null);
    let defaultLat = '';
    let defaultLng = '';
    if (mapRef.current) {
      const center = mapRef.current.getCenter();
      defaultLat = center.lat.toFixed(6);
      defaultLng = center.lng.toFixed(6);
    }
    setFormData({ 
      name: '', 
      category: categories[0]?.name || 'Landmark', 
      location: '', 
      lat: defaultLat, 
      lng: defaultLng, 
      status: 'Active', 
      image: '',
      entry_fee: '0.0'
    });
    setIsModalOpen(true);
  };

  const handleEdit = (attraction) => {
    setEditingId(attraction.id);
    setFormData({
      name: attraction.name,
      category: attraction.category_name || 'Landmark',
      location: attraction.address || '',
      lat: attraction.latitude.toString(),
      lng: attraction.longitude.toString(),
      status: attraction.is_active ? 'Active' : 'Inactive',
      image: attraction.photo_urls && attraction.photo_urls[0] ? attraction.photo_urls[0] : '',
      entry_fee: attraction.entry_fee ? attraction.entry_fee.toString() : '0.0'
    });
    setIsModalOpen(true);
  };

  const handleImageChange = (e) => {
    const file = e.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onloadend = () => {
        setFormData({ ...formData, image: reader.result });
      };
      reader.readAsDataURL(file);
    }
  };

  const handleSave = async (e) => {
    e.preventDefault();
    const category_id = categories.find(c => c.name === formData.category)?.id || null;

    const payload = {
      name: formData.name,
      latitude: parseFloat(formData.lat),
      longitude: parseFloat(formData.lng),
      category_id: category_id,
      address: formData.location,
      entry_fee: parseFloat(formData.entry_fee) || 0.0,
      currency: "USD",
      is_active: formData.status === 'Active',
      photo_urls: formData.image ? [formData.image] : []
    };

    try {
      if (editingId !== null) {
        await apiPut(`/admin/attractions/${editingId}`, payload);
        alert('Attraction updated successfully!');
      } else {
        await apiPost('/admin/attractions', payload);
        alert('Attraction created successfully!');
      }
      setIsModalOpen(false);
      refetch();
    } catch (err) {
      alert(`Failed to save attraction: ${err.message}`);
    }
  };

  const handleDelete = async (id) => {
    if (!confirm('Are you sure you want to delete this attraction?')) return;
    try {
      await apiDelete(`/admin/attractions/${id}`);
      refetch();
      if (selectedAttraction?.id === id) {
        setSelectedAttraction(null);
      }
    } catch (err) {
      alert(`Failed to delete attraction: ${err.message}`);
    }
  };

  if (error) {
    return (
      <div className="login-error" style={{ margin: '20px' }}>
        Failed to load attractions: {error}
      </div>
    );
  }

  return (
    <div style={{ position: 'relative' }}>
      {/* Premium Hero Banner */}
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
          <h2 style={{ fontSize: '22px', fontWeight: 800, margin: 0, letterSpacing: '-0.5px' }}>Saved Places &amp; Attractions</h2>
          <p style={{ margin: '4px 0 0 0', opacity: 0.9, fontSize: '13px', fontWeight: 500 }}>
            Visualizing and managing <strong style={{ color: '#fff', background: 'rgba(255,255,255,0.2)', padding: '2px 8px', borderRadius: '12px' }}>{totalCount}</strong> places saved in your backend database.
          </p>
        </div>
        <button className="btn" onClick={openAddModal} style={{ 
          background: 'white', 
          color: 'var(--accent)', 
          padding: '10px 20px', 
          borderRadius: '10px',
          fontWeight: 800,
          fontSize: '13px',
          boxShadow: '0 4px 14px rgba(0,0,0,0.1)'
        }}>
          + Add New Place
        </button>
      </div>

      {/* Split screen content */}
      <div className="approvals-split">
        {/* Left Side: Table & Search */}
        <div className="approvals-list-col" style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          
          {/* Search Bar & Filters */}
          <div className="card" style={{ padding: '16px', marginBottom: '0px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '16px' }}>
            <div className="search-bar" style={{ width: '100%', maxWidth: '360px' }}>
              <input 
                type="text" 
                placeholder="Search saved places..." 
                value={searchVal}
                onChange={e => setSearchVal(e.target.value)}
              />
            </div>
            {loading && <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Updating list...</div>}
          </div>

          {/* Table Card */}
          <div className="card" style={{ padding: '0px', overflow: 'hidden' }}>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Category</th>
                    <th>Location</th>
                    <th>Coordinates</th>
                    <th>Status</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {attractions.length === 0 ? (
                    <tr>
                      <td colSpan="6" style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>
                        No attractions found. Add one above!
                      </td>
                    </tr>
                  ) : attractions.map(a => (
                    <tr 
                      key={a.id} 
                      className={`clickable-row ${selectedAttraction?.id === a.id ? 'selected' : ''}`} 
                      onClick={() => handleSelectAttraction(a)}
                    >
                      <td style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                          {a.photo_urls && a.photo_urls[0] ? (
                            <div style={{ width: '32px', height: '32px', borderRadius: '8px', backgroundImage: `url(${a.photo_urls[0]})`, backgroundSize: 'cover', backgroundPosition: 'center', flexShrink: 0 }} />
                          ) : (
                            <div style={{ width: '32px', height: '32px', borderRadius: '8px', background: 'var(--accent-light)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                              <MapPinIcon size={16} />
                            </div>
                          )}
                          {a.name}
                        </div>
                      </td>
                      <td><span className="badge badge-blue">{a.category_name || 'General'}</span></td>
                      <td>{a.address || '—'}</td>
                      <td style={{ fontSize: '11.5px', color: 'var(--text-secondary)', fontFamily: 'monospace', letterSpacing: '0.5px' }}>
                        {a.latitude.toFixed(6)}, {a.longitude.toFixed(6)}
                      </td>
                      <td>
                        <span className={`badge ${a.is_active ? 'badge-green' : 'badge-yellow'}`}>
                          {a.is_active ? 'Active' : 'Inactive'}
                        </span>
                      </td>
                      <td>
                        <div style={{ display: 'flex', gap: '8px' }} onClick={e => e.stopPropagation()}>
                          <button className="btn btn-ghost" style={{ padding: '6px' }} title="Edit" onClick={() => handleEdit(a)}>
                            <EditIcon size={14} />
                          </button>
                          <button className="btn btn-ghost" style={{ padding: '6px', color: 'var(--danger)', borderColor: 'rgba(229,57,53,0.15)' }} title="Delete" onClick={() => handleDelete(a.id)}>
                            <TrashIcon size={14} />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* Right Side: Map */}
        <div className="approvals-map-col">
          <div className="map-card" style={{ padding: '16px' }}>
            <div className="card-title" style={{ marginBottom: '8px', fontSize: '15px', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <MapPinIcon size={16} style={{ color: 'var(--accent)' }} />
              Saved Places Map
            </div>
            <div id="attractions-map" className="map-container" style={{ height: '480px', overflow: 'hidden', zIndex: 1 }}></div>
            <div style={{ 
              fontSize: '11.5px', 
              color: 'var(--text-secondary)', 
              marginTop: '10px', 
              fontStyle: 'italic',
              display: 'flex',
              alignItems: 'center',
              gap: '6px'
            }}>
              <span>📍 Click pins to view details. Clicking table rows will pan the map.</span>
            </div>
          </div>
        </div>
      </div>

      {isModalOpen && (
        <div className="modal-overlay" onClick={() => setIsModalOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '600px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ fontSize: '18px', fontWeight: 800 }}>{editingId ? 'Edit Attraction' : 'Add New Attraction'}</h3>
              <button className="btn btn-ghost" style={{ padding: '6px', borderRadius: '50%' }} onClick={() => setIsModalOpen(false)}>
                <CrossIcon size={16} />
              </button>
            </div>
            
            <form onSubmit={handleSave}>
              <div className="form-group">
                <label className="form-label">Attraction Name</label>
                <input type="text" className="form-input" placeholder="e.g. Statue of Liberty" required value={formData.name} onChange={e => setFormData({...formData, name: e.target.value})} />
              </div>
              <div className="form-group">
                <label className="form-label">Attraction Image (Data URL/Link)</label>
                <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
                  {formData.image && (
                    <div style={{ width: '60px', height: '60px', borderRadius: '10px', backgroundImage: `url(${formData.image})`, backgroundSize: 'cover', backgroundPosition: 'center', border: '1px solid var(--border)', flexShrink: 0 }} />
                  )}
                  <input type="file" accept="image/*" onChange={handleImageChange} className="form-input" style={{ padding: '8px 12px', fontSize: '13px' }} />
                </div>
              </div>
              
              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Category</label>
                  <select className="form-select" value={formData.category} onChange={e => setFormData({...formData, category: e.target.value})}>
                    {categories.map(c => (
                      <option key={c.id} value={c.name}>{c.name}</option>
                    ))}
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Location (City, Country / Address)</label>
                  <input type="text" className="form-input" placeholder="e.g. New York, USA" required value={formData.location} onChange={e => setFormData({...formData, location: e.target.value})} />
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Latitude</label>
                  <input type="number" step="any" className="form-input" placeholder="40.6892" required value={formData.lat} onChange={e => setFormData({...formData, lat: e.target.value})} />
                </div>
                <div className="form-group">
                  <label className="form-label">Longitude</label>
                  <input type="number" step="any" className="form-input" placeholder="-74.0445" required value={formData.lng} onChange={e => setFormData({...formData, lng: e.target.value})} />
                </div>
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Entry Fee (USD)</label>
                  <input type="number" step="0.01" className="form-input" value={formData.entry_fee} onChange={e => setFormData({...formData, entry_fee: e.target.value})} />
                </div>
                <div className="form-group">
                  <label className="form-label">Status</label>
                  <select className="form-select" value={formData.status} onChange={e => setFormData({...formData, status: e.target.value})}>
                    <option value="Active">Active (Visible in App)</option>
                    <option value="Inactive">Inactive (Hidden)</option>
                  </select>
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '32px' }}>
                <button type="button" className="btn btn-ghost" onClick={() => setIsModalOpen(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary" style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <PlusIcon size={16} /> Save Attraction
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
