import { useState } from 'react';
import { apiDelete, apiPatch, apiPost, useApi } from '../api';
import { EmptyState, Modal, PageError, PageLoading, Switch, Toast } from '../components/Kit';
import { EditIcon, PlusIcon, TrashIcon, UsersIcon } from '../components/Icons';
import { useToast } from '../hooks';

const formatDate = (value) => (value
  ? new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  : 'Never');

/** A password the admin can pass on: 14 characters, no look-alikes. */
function suggestPassword() {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = window.crypto.getRandomValues(new Uint8Array(14));
  return [...bytes].map((b) => letters[b % letters.length]).join('');
}

function PasswordInput({ value, onChange }) {
  return (
    <div style={{ display: 'flex', gap: 8 }}>
      <input
        className="form-input" type="text" minLength={10} maxLength={128} value={value}
        autoComplete="new-password" onChange={(e) => onChange(e.target.value)}
      />
      <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange(suggestPassword())}>Suggest</button>
    </div>
  );
}

/**
 * The people who write City Tours guides. They sign in on this panel's own
 * sign-in page with their email and the password set here, and see only City
 * Tours. Switching a login off or setting a new password signs them out.
 */
export default function CityTourCreators() {
  const { data, loading, error, refetch } = useApi('/admin/city-tours/creators');
  const [adding, setAdding] = useState(null);
  const [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(false);
  const [toast, notify] = useToast(5000);

  const create = async () => {
    setSaving(true);
    try {
      await apiPost('/admin/city-tours/creators', adding);
      notify(`Added. Send ${adding.email} the password; they sign in at ${window.location.origin}.`);
      setAdding(null);
      refetch();
    } catch (err) {
      notify(err.message || 'Could not add the creator.', 'error');
    } finally {
      setSaving(false);
    }
  };

  const update = async (creator, patch, done) => {
    setSaving(true);
    try {
      await apiPatch(`/admin/city-tours/creators/${creator.id}`, patch);
      notify(done);
      setEditing(null);
      refetch();
    } catch (err) {
      notify(err.message || 'Could not save.', 'error');
    } finally {
      setSaving(false);
    }
  };

  const remove = async (creator) => {
    if (!confirm(`Remove ${creator.name}'s login? Their guides stay, under their name.`)) return;
    try {
      await apiDelete(`/admin/city-tours/creators/${creator.id}`);
      notify('Login removed');
      refetch();
    } catch (err) {
      notify(err.message || 'Could not remove the login.', 'error');
    }
  };

  if (error && !data) return <PageError error={error} onRetry={refetch} />;

  return (
    <div>
      <div className="xp-toolbar">
        <div className="xp-section-hint" style={{ margin: 0 }}>
          Creators sign in at <strong>{window.location.origin}</strong> with their email and see only City Tours.
        </div>
        <button type="button" className="btn btn-primary btn-sm" onClick={() => setAdding({ name: '', email: '', password: suggestPassword() })}>
          <PlusIcon size={14} /> Add creator
        </button>
      </div>

      {loading && !data ? <PageLoading /> : !data?.length ? (
        <EmptyState icon={<UsersIcon size={28} />} title="No content creators yet">
          Add the people who write City Tours guides.
        </EmptyState>
      ) : (
        <div className="card table-wrap ctt-card">
          <table className="ctt-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th className="num">Guides</th>
                <th className="num">Live</th>
                <th>Last sign-in</th>
                <th>Login</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {data.map((c) => (
                <tr key={c.id}>
                  <td><strong>{c.name}</strong></td>
                  <td>{c.email}</td>
                  <td className="num">{c.tour_count}</td>
                  <td className="num">{c.live_count}</td>
                  <td>{formatDate(c.last_login_at)}</td>
                  <td>
                    <Switch
                      checked={c.is_active} disabled={saving}
                      label={c.is_active ? 'On' : 'Off'}
                      onChange={(on) => update(c, { is_active: on }, on ? 'Login switched on' : 'Login switched off and signed out')}
                    />
                  </td>
                  <td style={{ whiteSpace: 'nowrap', textAlign: 'right' }}>
                    <button type="button" className="icon-btn" title="Rename or set a new password" onClick={() => setEditing({ ...c, password: '' })}>
                      <EditIcon size={15} />
                    </button>
                    <button type="button" className="icon-btn danger" title="Remove login" onClick={() => remove(c)}>
                      <TrashIcon size={15} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {adding && (
        <Modal title="Add a content creator" onClose={() => setAdding(null)} maxWidth="480px">
          <div className="form-group">
            <label className="form-label">Name *</label>
            <input className="form-input" maxLength={120} value={adding.name} onChange={(e) => setAdding({ ...adding, name: e.target.value })} />
          </div>
          <div className="form-group">
            <label className="form-label">Email (their sign-in name) *</label>
            <input className="form-input" type="email" maxLength={255} value={adding.email} onChange={(e) => setAdding({ ...adding, email: e.target.value })} />
          </div>
          <div className="form-group">
            <label className="form-label">Password * <span className="muted">(10 characters or more)</span></label>
            <PasswordInput value={adding.password} onChange={(password) => setAdding({ ...adding, password })} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setAdding(null)}>Cancel</button>
            <button
              type="button" className="btn btn-primary btn-sm" onClick={create}
              disabled={saving || !adding.name.trim() || !adding.email.trim() || adding.password.length < 10}
            >
              {saving ? 'Adding…' : 'Add creator'}
            </button>
          </div>
        </Modal>
      )}

      {editing && (
        <Modal title={`Edit ${editing.name}`} onClose={() => setEditing(null)} maxWidth="480px">
          <div className="form-group">
            <label className="form-label">Name</label>
            <input className="form-input" maxLength={120} value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
          </div>
          <div className="form-group">
            <label className="form-label">New password <span className="muted">(leave empty to keep the current one)</span></label>
            <PasswordInput value={editing.password} onChange={(password) => setEditing({ ...editing, password })} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setEditing(null)}>Cancel</button>
            <button
              type="button" className="btn btn-primary btn-sm"
              disabled={saving || !editing.name.trim() || (editing.password && editing.password.length < 10)}
              onClick={() => update(
                editing,
                { name: editing.name.trim(), ...(editing.password ? { password: editing.password } : {}) },
                editing.password ? 'Saved. The new password signs them out everywhere.' : 'Saved',
              )}
            >
              {saving ? 'Saving…' : 'Save'}
            </button>
          </div>
        </Modal>
      )}
      <Toast toast={toast} />
    </div>
  );
}
