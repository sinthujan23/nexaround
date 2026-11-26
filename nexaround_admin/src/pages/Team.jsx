import { useState } from 'react';
import { apiDelete, apiPatch, apiPost, useApi } from '../api';
import { Badge, EmptyState, Modal, PageError, PageLoading, Switch, Toast } from '../components/Kit';
import { EditIcon, PlusIcon, TrashIcon, UsersIcon } from '../components/Icons';
import { useToast } from '../hooks';
import {
  CITY_TOURS, EXPERIENCES, FEEDBACK, MUSEUMS, SUPPORT_INBOX, TRAVEL_BYTES,
} from '../session';

// The areas a login can open, in the order the sidebar shows them.
const AREAS = [
  [TRAVEL_BYTES, 'TravelBytes'],
  [MUSEUMS, 'Museums'],
  [EXPERIENCES, 'Experiences'],
  [CITY_TOURS, 'City Guides'],
  [SUPPORT_INBOX, 'Support inbox'],
  [FEEDBACK, 'Feedback & surveys'],
];

const formatDate = (value) => (value
  ? new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
  : 'Never');

/** A password the admin can pass on: 14 characters, no look-alikes. */
function suggestPassword() {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = window.crypto.getRandomValues(new Uint8Array(14));
  return [...bytes].map((b) => letters[b % letters.length]).join('');
}

function PasswordInput({ id, value, onChange, invalid }) {
  return (
    <div style={{ display: 'flex', gap: 8 }}>
      <input
        id={id} className="form-input" type="text" maxLength={128} value={value} aria-invalid={invalid || undefined}
        autoComplete="new-password" onChange={(e) => onChange(e.target.value)}
      />
      <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange(suggestPassword())}>Suggest</button>
    </div>
  );
}

/** Which areas the login opens and, for City Guides, who puts guides live. */
function AccessFields({ value, onChange, error }) {
  const toggle = (area, on) => onChange({
    ...value,
    sections: on
      ? AREAS.map(([key]) => key).filter((key) => key === area || value.sections.includes(key))
      : value.sections.filter((key) => key !== area),
  });
  return (
    <>
      <div className="form-group">
        <label className="form-label">What they can open *</label>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {AREAS.map(([key, label]) => (
            <Switch key={key} checked={value.sections.includes(key)} label={label} onChange={(on) => toggle(key, on)} />
          ))}
        </div>
        <FieldError message={error} />
      </div>
      {value.sections.includes(CITY_TOURS) && (
        <div className="form-group">
          <label className="form-label">City Guides</label>
          <select
            className="form-input" value={value.can_publish_guides ? 'publish' : 'review'}
            onChange={(e) => onChange({ ...value, can_publish_guides: e.target.value === 'publish' })}
          >
            <option value="review">Own guides only, each sent for admin approval</option>
            <option value="publish">All guides, puts them live themselves</option>
          </select>
        </div>
      )}
      <div className="xp-section-hint" style={{ margin: '0 0 16px' }}>
        They add and edit only. Deleting, approvals, enquiries, reviews, commission and partner logins stay with the admin.
      </div>
    </>
  );
}

// The form's fields, in the order they show: the first one wrong gets focus.
const FIELD_IDS = { name: 'team-name', email: 'team-email', password: 'team-password', sections: null };

/** What is wrong with each field, by field; empty when the form can be saved.
 * `adding` is the new-login form (the edit form has no email, and an empty
 * password there keeps the current one). */
function fieldErrors(form, adding) {
  const errors = {};
  if (!form.name.trim()) errors.name = 'Add their name.';
  const email = (form.email || '').trim().toLowerCase();
  if (adding && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    errors.email = 'Type their full email address, e.g. name@nexaround.com.';
  } else if (adding && form.takenEmail === email) {
    errors.email = 'There is already a team login with this email.';
  }
  if ((adding || form.password) && form.password.length < 10) {
    errors.password = `Use 10 characters or more (now ${form.password.length}).`;
  }
  if (!form.sections.length) errors.sections = 'Switch on at least one area.';
  return errors;
}

/** Red line under a field. */
function FieldError({ message }) {
  return message ? <div className="form-field-error" role="alert">{message}</div> : null;
}

/** Shows the form's problems and puts the cursor in the first wrong field.
 * True when there were none and saving can go ahead. */
function checkForm(form, setForm, adding) {
  const errors = fieldErrors(form, adding);
  const first = Object.keys(FIELD_IDS).find((key) => errors[key]);
  if (!first) return true;
  setForm({ ...form, checked: true });
  if (FIELD_IDS[first]) document.getElementById(FIELD_IDS[first])?.focus();
  return false;
}

const sameAccess = (a, b) => a.can_publish_guides === b.can_publish_guides
  && a.sections.length === b.sections.length && a.sections.every((s) => b.sections.includes(s));

/**
 * Team logins: the people other than the admin who use this panel (data entry
 * staff and City Guides writers). They sign in on this panel's own sign-in
 * page with their email and the password set here, and see only the areas
 * ticked for them. Changing those, setting a new password or switching a
 * login off signs them out.
 */
export default function Team() {
  const { data, loading, error, refetch } = useApi('/admin/team');
  const [adding, setAdding] = useState(null);
  const [editing, setEditing] = useState(null);
  const [saving, setSaving] = useState(false);
  const [toast, notify] = useToast(5000);

  const create = async () => {
    if (!checkForm(adding, setAdding, true)) return;
    const email = adding.email.trim();
    setSaving(true);
    try {
      await apiPost('/admin/team', {
        name: adding.name.trim(), email, password: adding.password,
        sections: adding.sections, can_publish_guides: adding.can_publish_guides,
      });
      notify(`Added. Send ${email} the password; they sign in at ${window.location.origin}.`);
      setAdding(null);
      refetch();
    } catch (err) {
      if (err.status === 409) {
        setAdding((form) => ({ ...form, checked: true, takenEmail: email.toLowerCase() }));
        document.getElementById(FIELD_IDS.email)?.focus();
      } else {
        notify(err.message || 'Could not add the login.', 'error');
      }
    } finally {
      setSaving(false);
    }
  };

  const update = async (member, patch, done) => {
    setSaving(true);
    try {
      await apiPatch(`/admin/team/${member.id}`, patch);
      notify(done);
      setEditing(null);
      refetch();
    } catch (err) {
      notify(err.message || 'Could not save.', 'error');
    } finally {
      setSaving(false);
    }
  };

  const remove = async (member) => {
    if (!confirm(`Remove ${member.name}'s login? Their guides stay, under their name.`)) return;
    try {
      await apiDelete(`/admin/team/${member.id}`);
      notify('Login removed');
      refetch();
    } catch (err) {
      notify(err.message || 'Could not remove the login.', 'error');
    }
  };

  const saveEdit = () => {
    if (!checkForm(editing, setEditing, false)) return;
    const original = data.find((m) => m.id === editing.id);
    const accessChanged = !sameAccess(editing, original);
    update(
      editing,
      {
        name: editing.name.trim(),
        ...(accessChanged ? { sections: editing.sections, can_publish_guides: editing.can_publish_guides } : {}),
        ...(editing.password ? { password: editing.password } : {}),
      },
      editing.password || accessChanged ? 'Saved. They are signed out and see the change when they sign in again.' : 'Saved',
    );
  };

  if (error && !data) return <PageError error={error} onRetry={refetch} />;

  // Field problems show only once Add / Save has been pressed, then follow
  // the typing, so an empty form never opens in red.
  const addErrors = adding?.checked ? fieldErrors(adding, true) : {};
  const editErrors = editing?.checked ? fieldErrors(editing, false) : {};

  return (
    <div>
      <div className="xp-toolbar">
        <div className="xp-section-hint" style={{ margin: 0 }}>
          Team members sign in at <strong>{window.location.origin}</strong> with their email and see only the areas ticked for them.
        </div>
        <button
          type="button" className="btn btn-primary btn-sm"
          onClick={() => setAdding({
            name: '', email: '', password: suggestPassword(), sections: [], can_publish_guides: false,
          })}
        >
          <PlusIcon size={14} /> Add login
        </button>
      </div>

      {loading && !data ? <PageLoading /> : !data?.length ? (
        <EmptyState icon={<UsersIcon size={28} />} title="No team logins yet">
          Add the people who enter City Guides, Experiences, TravelBytes or Museums.
        </EmptyState>
      ) : (
        <div className="card table-wrap ctt-card">
          <table className="ctt-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Can open</th>
                <th className="num">Guides</th>
                <th className="num">Live</th>
                <th>Last sign-in</th>
                <th>Login</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {data.map((m) => (
                <tr key={m.id}>
                  <td><strong>{m.name}</strong></td>
                  <td>{m.email}</td>
                  <td>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                      {AREAS.filter(([key]) => m.sections.includes(key)).map(([key, label]) => (
                        <Badge
                          key={key} tone={key === CITY_TOURS && m.can_publish_guides ? 'green' : 'ghost'}
                          title={key === CITY_TOURS ? (m.can_publish_guides ? 'Puts guides live themselves' : 'Guides need admin approval') : undefined}
                        >
                          {key === CITY_TOURS ? `${label} · ${m.can_publish_guides ? 'publishes' : 'needs approval'}` : label}
                        </Badge>
                      ))}
                    </div>
                  </td>
                  <td className="num">{m.tour_count}</td>
                  <td className="num">{m.live_count}</td>
                  <td>{formatDate(m.last_login_at)}</td>
                  <td>
                    <Switch
                      checked={m.is_active} disabled={saving}
                      label={m.is_active ? 'On' : 'Off'}
                      onChange={(on) => update(m, { is_active: on }, on ? 'Login switched on' : 'Login switched off and signed out')}
                    />
                  </td>
                  <td style={{ whiteSpace: 'nowrap', textAlign: 'right' }}>
                    <button type="button" className="icon-btn" title="Edit access, rename or set a new password" onClick={() => setEditing({ ...m, password: '' })}>
                      <EditIcon size={15} />
                    </button>
                    <button type="button" className="icon-btn danger" title="Remove login" onClick={() => remove(m)}>
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
        <Modal title="Add a team login" onClose={() => setAdding(null)} maxWidth="480px">
          <div className="form-group">
            <label className="form-label" htmlFor={FIELD_IDS.name}>Name *</label>
            <input
              id={FIELD_IDS.name} className="form-input" maxLength={120} value={adding.name}
              aria-invalid={!!addErrors.name || undefined}
              onChange={(e) => setAdding({ ...adding, name: e.target.value })}
            />
            <FieldError message={addErrors.name} />
          </div>
          <div className="form-group">
            <label className="form-label" htmlFor={FIELD_IDS.email}>Email (their sign-in name) *</label>
            <input
              id={FIELD_IDS.email} className="form-input" type="email" maxLength={255} value={adding.email}
              aria-invalid={!!addErrors.email || undefined}
              onChange={(e) => setAdding({ ...adding, email: e.target.value })}
            />
            <FieldError message={addErrors.email} />
          </div>
          <div className="form-group">
            <label className="form-label" htmlFor={FIELD_IDS.password}>Password * <span className="muted">(10 characters or more)</span></label>
            <PasswordInput
              id={FIELD_IDS.password} value={adding.password} invalid={!!addErrors.password}
              onChange={(password) => setAdding({ ...adding, password })}
            />
            <FieldError message={addErrors.password} />
          </div>
          <AccessFields value={adding} onChange={setAdding} error={addErrors.sections} />
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setAdding(null)}>Cancel</button>
            <button type="button" className="btn btn-primary btn-sm" onClick={create} disabled={saving}>
              {saving ? 'Adding…' : 'Add login'}
            </button>
          </div>
        </Modal>
      )}

      {editing && (
        <Modal title={`Edit ${editing.name}`} onClose={() => setEditing(null)} maxWidth="480px">
          <div className="form-group">
            <label className="form-label" htmlFor={FIELD_IDS.name}>Name</label>
            <input
              id={FIELD_IDS.name} className="form-input" maxLength={120} value={editing.name}
              aria-invalid={!!editErrors.name || undefined}
              onChange={(e) => setEditing({ ...editing, name: e.target.value })}
            />
            <FieldError message={editErrors.name} />
          </div>
          <AccessFields value={editing} onChange={setEditing} error={editErrors.sections} />
          <div className="form-group">
            <label className="form-label" htmlFor={FIELD_IDS.password}>New password <span className="muted">(leave empty to keep the current one)</span></label>
            <PasswordInput
              id={FIELD_IDS.password} value={editing.password} invalid={!!editErrors.password}
              onChange={(password) => setEditing({ ...editing, password })}
            />
            <FieldError message={editErrors.password} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => setEditing(null)}>Cancel</button>
            <button type="button" className="btn btn-primary btn-sm" disabled={saving} onClick={saveEdit}>
              {saving ? 'Saving…' : 'Save'}
            </button>
          </div>
        </Modal>
      )}
      <Toast toast={toast} />
    </div>
  );
}
