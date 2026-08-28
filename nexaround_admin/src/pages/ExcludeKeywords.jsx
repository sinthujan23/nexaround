import React, { useState } from 'react';
import { PlusIcon, TrashIcon } from '../components/Icons';
import { useApi, apiPost, apiDelete } from '../api';

export default function ExcludeKeywords() {
  const { data, loading, error, refetch } = useApi('/admin/excluded-keywords');
  const keywords = data || [];

  const [newKeyword, setNewKeyword] = useState('');
  const [saving, setSaving] = useState(false);

  const handleAdd = async (e) => {
    e.preventDefault();
    const keyword = newKeyword.trim();
    if (!keyword) return;

    setSaving(true);
    try {
      await apiPost('/admin/excluded-keywords', { keyword });
      setNewKeyword('');
      refetch();
    } catch (err) {
      alert(`Failed to add keyword: ${err.message}`);
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id) => {
    if (!confirm('Remove this keyword? Matching places will show in Around You again.')) return;
    try {
      await apiDelete(`/admin/excluded-keywords/${id}`);
      refetch();
    } catch (err) {
      alert(`Failed to remove keyword: ${err.message}`);
    }
  };

  return (
    <div>
      <div className="card" style={{ padding: '16px', marginBottom: '16px' }}>
        <p style={{ margin: '0 0 16px 0', color: 'var(--text-secondary)', fontSize: '13px' }}>
          A place whose name matches a keyword here (whole word, e.g. "pond" matches
          "Pond View" but not "Pondicherry Cafe") is hidden from the Around You cards.
          It still appears in Discover and everywhere else in the app.
        </p>
        <form onSubmit={handleAdd} style={{ display: 'flex', gap: '12px' }}>
          <input
            type="text"
            className="form-input"
            placeholder="e.g. pond"
            value={newKeyword}
            onChange={e => setNewKeyword(e.target.value)}
            style={{ maxWidth: '320px' }}
          />
          <button type="submit" className="btn btn-primary" disabled={saving || !newKeyword.trim()}>
            <PlusIcon size={16} /> Add Keyword
          </button>
        </form>
      </div>

      {error && (
        <div className="login-error" style={{ margin: '0 0 16px 0' }}>
          Failed to load excluded keywords: {error}
        </div>
      )}

      <div className="card">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Keyword</th>
                <th>Added</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {keywords.length === 0 ? (
                <tr>
                  <td colSpan="3" style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>
                    {loading ? 'Loading...' : 'No excluded keywords yet. Add one above.'}
                  </td>
                </tr>
              ) : keywords.map(k => (
                <tr key={k.id}>
                  <td style={{ fontWeight: 600, color: 'var(--text-primary)' }}>{k.keyword}</td>
                  <td style={{ color: 'var(--text-secondary)' }}>
                    {new Date(k.created_at).toLocaleDateString()}
                  </td>
                  <td>
                    <button
                      className="btn btn-ghost"
                      style={{ padding: '4px', color: 'var(--danger)' }}
                      title="Remove"
                      onClick={() => handleDelete(k.id)}
                    >
                      <TrashIcon size={16} />
                    </button>
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
