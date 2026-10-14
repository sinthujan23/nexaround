import { useState } from 'react';
import { PlusIcon, TrashIcon, EyeOffIcon } from '../components/Icons';
import { Card, Badge } from '../components/Kit';
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
      <Card style={{ padding: '20px 24px', marginBottom: '20px', borderRadius: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '12px', flexWrap: 'wrap', gap: '8px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <EyeOffIcon size={18} style={{ color: 'var(--accent)' }} />
            <h2 style={{ fontSize: '16px', fontWeight: 700, margin: 0, color: 'var(--text-primary)' }}>
              Exclude Keywords (Around You)
            </h2>
          </div>
          <Badge tone="ghost" style={{ fontSize: '11px', fontWeight: 600, padding: '4px 10px' }}>
            Around You Filter
          </Badge>
        </div>

        <p style={{ margin: '0 0 16px 0', color: 'var(--text-secondary)', fontSize: '13px', lineHeight: 1.5 }}>
          A place whose name matches a keyword here (whole word, e.g. "pond" matches
          "Pond View" but not "Pondicherry Cafe") is hidden from the <strong>Around You</strong> cards.
          It still appears in Discover and everywhere else in the app.
        </p>

        <form onSubmit={handleAdd} style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
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
      </Card>

      {error && (
        <div className="login-error" style={{ margin: '0 0 16px 0' }}>
          Failed to load excluded keywords: {error}
        </div>
      )}

      <Card
        title={
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span>Excluded Keywords</span>
            <span style={{ fontSize: '12px', fontWeight: 500, color: 'var(--text-secondary)' }}>
              ({keywords.length})
            </span>
          </div>
        }
      >
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
      </Card>
    </div>
  );
}
