import React, { useState } from 'react';
import { ImageIcon, PlusIcon, TrashIcon, CheckIcon, CrossIcon, MapPinIcon, UsersIcon } from '../components/Icons';

export default function Media() {
  const [media, setMedia] = useState([
    {
      id: 1,
      image: 'https://images.unsplash.com/photo-1552832230-c0197dd311b5?auto=format&fit=crop&w=500&q=60',
      location: 'Colosseum',
      lat: 41.8902,
      lng: 12.4922,
      uploader: 'User (john_doe)',
      status: 'Pending'
    },
    {
      id: 2,
      image: 'https://images.unsplash.com/photo-1543349689-9a4d426bee8e?auto=format&fit=crop&w=500&q=60',
      location: 'Eiffel Tower',
      lat: 48.8584,
      lng: 2.2945,
      uploader: 'Admin',
      status: 'Approved'
    },
    {
      id: 3,
      image: 'https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?auto=format&fit=crop&w=500&q=60',
      location: 'Golden Gate Bridge',
      lat: 37.8199,
      lng: -122.4783,
      uploader: 'User (travel_guy)',
      status: 'Approved'
    }
  ]);

  const [isModalOpen, setIsModalOpen] = useState(false);
  const [formData, setFormData] = useState({ location: '', lat: '', lng: '', image: '' });

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
    const newId = media.length ? Math.max(...media.map(m => m.id)) + 1 : 1;
    setMedia([{ ...formData, id: newId, uploader: 'Admin', status: 'Approved' }, ...media]);
    setIsModalOpen(false);
    setFormData({ location: '', lat: '', lng: '', image: '' });
  };

  const handleStatus = (id, newStatus) => {
    setMedia(media.map(m => m.id === id ? { ...m, status: newStatus } : m));
  };

  const handleDelete = (id) => {
    setMedia(media.filter(m => m.id !== id));
  };

  return (
    <div style={{ position: 'relative' }}>
      <div className="card-header" style={{ marginBottom: '24px' }}>
        <div>
          <div className="card-title">Media Library</div>
          <div style={{ fontSize: '13px', color: 'var(--text-secondary)', marginTop: '4px' }}>
            Review user-submitted places or add missing attractions manually.
          </div>
        </div>
        <button className="btn btn-primary" style={{ display: 'flex', alignItems: 'center', gap: '8px' }} onClick={() => setIsModalOpen(true)}>
          <PlusIcon size={16} /> Add Media
        </button>
      </div>

      <div className="three-col">
        {media.map(m => (
          <div key={m.id} style={{ 
            background: 'var(--bg-card)', 
            borderRadius: '16px', 
            overflow: 'hidden', 
            border: `1px solid ${m.status === 'Pending' ? 'var(--warning)' : 'var(--border)'}`, 
            boxShadow: 'var(--shadow-sm)',
            transition: 'var(--transition)'
          }}>
            {/* Image Thumbnail */}
            <div style={{ 
              height: '180px', 
              backgroundImage: `url(${m.image})`, 
              backgroundSize: 'cover', 
              backgroundPosition: 'center',
              position: 'relative'
            }}>
              {m.status === 'Pending' && (
                <div style={{ position: 'absolute', top: '12px', right: '12px', background: 'var(--warning)', color: '#fff', fontSize: '10px', fontWeight: 800, padding: '4px 10px', borderRadius: '12px', textTransform: 'uppercase', letterSpacing: '1px' }}>
                  Pending Review
                </div>
              )}
              {m.status === 'Approved' && (
                <div style={{ position: 'absolute', top: '12px', right: '12px', background: 'var(--accent)', color: '#fff', fontSize: '10px', fontWeight: 800, padding: '4px 10px', borderRadius: '12px', textTransform: 'uppercase', letterSpacing: '1px' }}>
                  Approved
                </div>
              )}
              {m.status === 'Rejected' && (
                <div style={{ position: 'absolute', top: '12px', right: '12px', background: 'var(--danger)', color: '#fff', fontSize: '10px', fontWeight: 800, padding: '4px 10px', borderRadius: '12px', textTransform: 'uppercase', letterSpacing: '1px' }}>
                  Rejected
                </div>
              )}
            </div>

            {/* Details */}
            <div style={{ padding: '20px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '12px' }}>
                <div>
                  <h4 style={{ fontSize: '15px', fontWeight: 800, color: 'var(--text-primary)', marginBottom: '4px' }}>{m.location}</h4>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '4px', fontSize: '11.5px', color: 'var(--text-secondary)', fontFamily: 'monospace' }}>
                    <MapPinIcon size={12} /> {m.lat}, {m.lng}
                  </div>
                </div>
                <button className="btn btn-ghost" style={{ padding: '6px', color: 'var(--danger)', border: 'none' }} onClick={() => handleDelete(m.id)} title="Delete">
                  <TrashIcon size={16} />
                </button>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: 'var(--text-secondary)', marginBottom: '20px' }}>
                <UsersIcon size={14} /> Uploaded by: <strong style={{ color: 'var(--text-primary)' }}>{m.uploader}</strong>
              </div>

              {/* Actions for Pending */}
              {m.status === 'Pending' && (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' }}>
                  <button className="action-btn approve" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', padding: '10px' }} onClick={() => handleStatus(m.id, 'Approved')}>
                    <CheckIcon size={14} /> Approve
                  </button>
                  <button className="action-btn reject" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px', padding: '10px' }} onClick={() => handleStatus(m.id, 'Rejected')}>
                    <CrossIcon size={14} /> Reject
                  </button>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {isModalOpen && (
        <div className="modal-overlay" onClick={() => setIsModalOpen(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: '500px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h3 style={{ fontSize: '18px', fontWeight: 800 }}>Add Media Manually</h3>
              <button className="btn btn-ghost" style={{ padding: '6px', borderRadius: '50%' }} onClick={() => setIsModalOpen(false)}>
                <CrossIcon size={16} />
              </button>
            </div>
            
            <form onSubmit={handleSave}>
              <div className="form-group">
                <label className="form-label">Media Image</label>
                <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
                  {formData.image ? (
                    <div style={{ width: '80px', height: '80px', borderRadius: '12px', backgroundImage: `url(${formData.image})`, backgroundSize: 'cover', backgroundPosition: 'center', border: '1px solid var(--border)', flexShrink: 0 }} />
                  ) : (
                    <div style={{ width: '80px', height: '80px', borderRadius: '12px', background: 'var(--bg-dark)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)', border: '1px dashed var(--border)', flexShrink: 0 }}>
                      <ImageIcon size={24} />
                    </div>
                  )}
                  <input type="file" accept="image/*" onChange={handleImageChange} required className="form-input" style={{ padding: '8px 12px', fontSize: '13px' }} />
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">Location Name</label>
                <input type="text" className="form-input" placeholder="e.g. Louvre Museum" required value={formData.location} onChange={e => setFormData({...formData, location: e.target.value})} />
              </div>

              <div className="form-grid-2">
                <div className="form-group">
                  <label className="form-label">Latitude</label>
                  <input type="number" step="any" className="form-input" placeholder="48.8606" required value={formData.lat} onChange={e => setFormData({...formData, lat: e.target.value})} />
                </div>
                <div className="form-group">
                  <label className="form-label">Longitude</label>
                  <input type="number" step="any" className="form-input" placeholder="2.3376" required value={formData.lng} onChange={e => setFormData({...formData, lng: e.target.value})} />
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '12px', marginTop: '32px' }}>
                <button type="button" className="btn btn-ghost" onClick={() => setIsModalOpen(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary" style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <PlusIcon size={16} /> Upload Media
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
