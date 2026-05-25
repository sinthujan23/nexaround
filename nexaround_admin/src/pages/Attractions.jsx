import React, { useState } from 'react';
import { MapPinIcon, PlusIcon, EditIcon, TrashIcon, CrossIcon } from '../components/Icons';

export default function Attractions() {
  const [attractions, setAttractions] = useState([
    { id: 1, name: "Eiffel Tower", category: "Landmark", status: "Active", location: "Paris, France", lat: 48.8584, lng: 2.2945 },
    { id: 2, name: "Louvre Museum", category: "Museum", status: "Active", location: "Paris, France", lat: 48.8606, lng: 2.3376 },
    { id: 3, name: "Grand Canyon", category: "Nature", status: "Active", location: "Arizona, USA", lat: 36.1069, lng: -112.1129 },
    { id: 4, name: "Colosseum", category: "Historical", status: "Inactive", location: "Rome, Italy", lat: 41.8902, lng: 12.4922 },
  ]);

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingId, setEditingId] = useState(null);
  const [formData, setFormData] = useState({
    name: '', category: 'Landmark', location: '', lat: '', lng: '', status: 'Active', image: ''
  });

  const openAddModal = () => {
    setEditingId(null);
    setFormData({ name: '', category: 'Landmark', location: '', lat: '', lng: '', status: 'Active', image: '' });
    setIsModalOpen(true);
  };

  const handleEdit = (attraction) => {
    setEditingId(attraction.id);
    setFormData({
      name: attraction.name,
      category: attraction.category,
      location: attraction.location,
      lat: attraction.lat,
      lng: attraction.lng,
      status: attraction.status,
      image: attraction.image || ''
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

  const handleSave = (e) => {
    e.preventDefault();
    if (editingId !== null) {
      setAttractions(attractions.map(a => (a.id === editingId ? { ...formData, id: editingId } : a)));
    } else {
      const newId = attractions.length ? Math.max(...attractions.map(a => a.id)) + 1 : 1;
      setAttractions([{ ...formData, id: newId }, ...attractions]);
    }
    setIsModalOpen(false);
  };

  const handleDelete = (id) => {
    setAttractions(attractions.filter(a => a.id !== id));
  };

  return (
    <div style={{ position: 'relative' }}>
      <div className="card-header" style={{ marginBottom: '20px' }}>
        <div className="card-title">Manage Attractions</div>
        <button className="btn btn-primary" style={{ display: 'flex', alignItems: 'center', gap: '8px' }} onClick={openAddModal}>
          <PlusIcon size={16} /> Add Attraction
        </button>
      </div>

      <div className="card">
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
                  <td colSpan="7" style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>No attractions found. Add one above!</td>
                </tr>
              ) : attractions.map(a => (
                <tr key={a.id}>
                  <td style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                      {a.image ? (
                        <div style={{ width: '32px', height: '32px', borderRadius: '8px', backgroundImage: `url(${a.image})`, backgroundSize: 'cover', backgroundPosition: 'center', flexShrink: 0 }} />
                      ) : (
                        <div style={{ width: '32px', height: '32px', borderRadius: '8px', background: 'var(--accent-light)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                          <MapPinIcon size={16} />
                        </div>
                      )}
                      {a.name}
                    </div>
                  </td>
                  <td><span className="badge badge-blue">{a.category}</span></td>
                  <td>{a.location}</td>
                  <td style={{ fontSize: '11.5px', color: 'var(--text-secondary)', fontFamily: 'monospace', letterSpacing: '0.5px' }}>
                    {a.lat}, {a.lng}
                  </td>
                  <td>
                    <span className={`badge ${a.status === 'Active' ? 'badge-green' : 'badge-yellow'}`}>
                      {a.status}
                    </span>
                  </td>
                  <td>
                    <div style={{ display: 'flex', gap: '8px' }}>
                      <button className="btn btn-ghost" style={{ padding: '6px' }} title="Edit" onClick={() => handleEdit(a)}><EditIcon size={14} /></button>
                      <button className="btn btn-ghost" style={{ padding: '6px', color: 'var(--danger)', borderColor: 'rgba(229,57,53,0.15)' }} title="Delete" onClick={() => handleDelete(a.id)}><TrashIcon size={14} /></button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
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
                <label className="form-label">Attraction Image</label>
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
                    <option>Landmark</option>
                    <option>Museum</option>
                    <option>Nature</option>
                    <option>Historical</option>
                    <option>Entertainment</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label">Location (City, Country)</label>
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

              <div className="form-group">
                <label className="form-label">Status</label>
                <select className="form-select" value={formData.status} onChange={e => setFormData({...formData, status: e.target.value})}>
                  <option value="Active">Active (Visible in App)</option>
                  <option value="Inactive">Inactive (Hidden)</option>
                </select>
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
