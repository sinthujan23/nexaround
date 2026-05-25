import React from 'react';
import { PlusIcon, EditIcon, TrashIcon } from '../components/Icons';

export default function Categories() {
  const mockCategories = [
    { id: 1, name: "Landmark", description: "Famous monuments and structures", count: 42 },
    { id: 2, name: "Museum", description: "Art, history, and science museums", count: 28 },
    { id: 3, name: "Nature", description: "Parks, trails, and natural wonders", count: 115 },
    { id: 4, name: "Historical", description: "Historical sites and ancient ruins", count: 56 },
  ];

  return (
    <div>
      <div className="card-header" style={{ marginBottom: '20px' }}>
        <div className="card-title">Manage Categories</div>
        <button className="btn btn-primary" onClick={() => alert('Opening Add Category Modal...')}>
          <PlusIcon size={16} /> Add Category
        </button>
      </div>

      <div className="card">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Description</th>
                <th>Attractions Count</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {mockCategories.map(c => (
                <tr key={c.id}>
                  <td style={{ color: 'var(--text-secondary)' }}>#{c.id}</td>
                  <td style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{c.name}</td>
                  <td style={{ color: 'var(--text-secondary)' }}>{c.description}</td>
                  <td><span className="badge badge-green">{c.count} places</span></td>
                  <td>
                    <div style={{ display: 'flex', gap: '8px' }}>
                      <button className="btn btn-ghost" style={{ padding: '4px' }} title="Edit"><EditIcon size={16} /></button>
                      <button className="btn btn-ghost" style={{ padding: '4px', color: 'var(--danger)' }} title="Delete"><TrashIcon size={16} /></button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
