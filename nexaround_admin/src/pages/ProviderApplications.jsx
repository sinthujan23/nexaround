import { useState } from 'react';
import { useApi, apiPatch } from '../api';
import {
  InboxIcon, MailIcon, PhoneIcon, RefreshIcon, WhatsAppIcon,
} from '../components/Icons';
import { Toast } from '../components/Kit';
import { useToast } from '../hooks';
import { notifyProviderApplicationsChanged } from '../providerApplications';

// Businesses asking to list their experiences, from the app's "List your
// experience" form. Nothing here publishes anything: once a business fits,
// add it as a vendor in Experiences and mark the application "Added".

const STATUSES = ['new', 'contacted', 'added', 'rejected'];
const STATUS_LABELS = { new: 'New', contacted: 'Contacted', added: 'Added', rejected: 'Not a fit' };
// The dot colours the Enquiries page uses for the same ideas.
const STATUS_DOT = { new: 'new', contacted: 'contacted', added: 'confirmed', rejected: 'closed' };
const FILTERS = [['new', 'New'], ['contacted', 'Contacted'], ['added', 'Added'], ['rejected', 'Not a fit'], ['', 'All']];
const TZ = 'Asia/Colombo';

const formatDateTime = (value) =>
  value
    ? new Date(value).toLocaleString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
    })
    : '—';

const formatAge = (value) => {
  if (!value) return '';
  const minutes = Math.floor((Date.now() - new Date(value).getTime()) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.floor(minutes / 60)}h`;
  if (minutes < 60 * 24 * 7) return `${Math.floor(minutes / 1440)}d`;
  return new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: TZ });
};

const digitsOnly = (phone) => (phone || '').replace(/[^0-9]/g, '');

const whatsAppLink = (a) => {
  const greeting = `Hi ${a.contact_name}, thanks for applying to list ${a.business_name} on NexAround.`;
  return `https://wa.me/${digitsOnly(a.contact_phone)}?text=${encodeURIComponent(greeting)}`;
};

// Links are typed freely; only full web addresses become clickable.
const linkify = (text) => (text || '').split(/\s+/).filter(Boolean).map((part, i) => (
  /^https?:\/\//i.test(part)
    ? <div key={i}><a href={part} target="_blank" rel="noreferrer">{part}</a></div>
    : <div key={i}>{part}</div>
));

/** Keyed by the application, so it starts from that one's saved notes. */
function NotesBox({ saved, saving, onSave }) {
  const [notes, setNotes] = useState(saved);
  return (
    <>
      <textarea
        className="form-textarea" rows={4} value={notes}
        placeholder="e.g. Called on WhatsApp, sending the partner form"
        onChange={(e) => setNotes(e.target.value)}
      />
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: 10 }}>
        <button
          className="btn btn-primary btn-sm"
          disabled={saving || notes === saved}
          onClick={() => onSave(notes)}
        >
          Save notes
        </button>
      </div>
    </>
  );
}

export default function ProviderApplications() {
  const [filter, setFilter] = useState('new');
  const { data, error, refetch } = useApi(
    `/admin/experiences/provider-applications${filter ? `?status=${filter}` : ''}`,
  );
  const [selectedId, setSelectedId] = useState(null);
  const [saving, setSaving] = useState(false);
  const [toast, notify] = useToast(3000);

  const items = data?.applications || [];
  const selected = items.find((a) => a.id === selectedId) || null;

  const save = async (body, done) => {
    setSaving(true);
    try {
      await apiPatch(`/admin/experiences/provider-applications/${selected.id}`, body);
      notifyProviderApplicationsChanged();
      await refetch();
      notify(done);
    } catch (err) {
      notify(err.message || 'Could not save.', 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div>
      <Toast toast={toast} />
      <div className="xp-toolbar">
        <div className="seg">
          {FILTERS.map(([value, label]) => (
            <button
              key={value || 'all'}
              className={`seg-btn ${filter === value ? 'active' : ''}`}
              onClick={() => { setFilter(value); setSelectedId(null); }}
            >
              {STATUS_DOT[value] && <span className={`dot dot-${STATUS_DOT[value]}`} />}
              {label}
              {value === 'new' && data?.new_count > 0 && <span className="seg-count">{data.new_count}</span>}
            </button>
          ))}
        </div>
        <div className="xp-toolbar-right">
          <button className="btn btn-ghost btn-sm" onClick={refetch} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      <div className={`xp-split ${selected ? 'has-selection' : ''}`}>
        <aside className="xp-pane xp-list-pane">
          <div className="xp-list-body">
            {!data && <div className="loader" />}
            {data && items.length === 0 && (
              <div className="xp-empty">
                <InboxIcon size={32} />
                <strong>{filter === 'new' ? 'No new applications' : 'Nothing here'}</strong>
                Businesses that tap “List your experience” in the app appear here.
              </div>
            )}
            {items.map((a) => (
              <button
                key={a.id}
                className={`xp-row ${selected?.id === a.id ? 'active' : ''}`}
                onClick={() => setSelectedId(a.id)}
                style={{ alignItems: 'flex-start' }}
              >
                <span className={`dot dot-${STATUS_DOT[a.status]}`} style={{ marginTop: 6 }} title={STATUS_LABELS[a.status]} />
                <div className="xp-row-main">
                  <div className="xp-row-title">{a.business_name}</div>
                  <div className="xp-row-sub" style={{ color: 'var(--text-primary)' }}>{a.contact_name}</div>
                  <div className="xp-row-sub">{[a.city, a.country_code].filter(Boolean).join(', ')}</div>
                </div>
                <div className="xp-row-side" title={formatDateTime(a.created_at)}>{formatAge(a.created_at)}</div>
              </button>
            ))}
          </div>
        </aside>

        <section className="xp-pane xp-detail-pane">
          {!selected && (
            <div className="xp-empty">
              <InboxIcon size={36} />
              <strong>Select an application</strong>
              Contact the business, then add it as a vendor in Experiences and mark it Added.
            </div>
          )}

          {selected && (
            <>
              <div className="xp-detail-head">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <button className="xp-back" onClick={() => setSelectedId(null)}>← All applications</button>
                  <div className="xp-detail-title">{selected.business_name}</div>
                  <div className="xp-detail-sub">Sent {formatDateTime(selected.created_at)}</div>
                </div>
                <span className="status-label">
                  <span className={`dot dot-${STATUS_DOT[selected.status]}`} /> {STATUS_LABELS[selected.status]}
                </span>
              </div>

              <div className="xp-body">
                <div className="xp-section">
                  <div className="contact-card">
                    <div className="contact-card-lines">
                      {selected.contact_name} · {selected.contact_phone}
                      <div><span>{selected.contact_email}</span></div>
                    </div>
                    <div className="contact-card-actions">
                      <a className="btn btn-whatsapp btn-sm" href={whatsAppLink(selected)} target="_blank" rel="noreferrer">
                        <WhatsAppIcon size={15} /> WhatsApp
                      </a>
                      <a className="btn btn-ghost btn-sm" href={`tel:${selected.contact_phone}`}>
                        <PhoneIcon size={14} /> Call
                      </a>
                      <a className="btn btn-ghost btn-sm" href={`mailto:${selected.contact_email}`}>
                        <MailIcon size={14} /> Email
                      </a>
                    </div>
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title" style={{ marginBottom: 14 }}>Application</div>
                  <dl className="dl-grid">
                    <div><dt>Location</dt><dd>{[selected.city, selected.country_code].filter(Boolean).join(', ')}</dd></div>
                    <div>
                      <dt>Links</dt>
                      <dd className={selected.links ? '' : 'muted'}>{selected.links ? linkify(selected.links) : 'None given'}</dd>
                    </div>
                  </dl>
                  <div className="dl-label" style={{ marginTop: 14 }}>What they offer</div>
                  <div className="quote" style={{ whiteSpace: 'pre-wrap' }}>{selected.offering}</div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Status</div>
                  <div className="xp-section-hint">Changes save straight away. Nothing is sent to the business.</div>
                  <div className="status-seg">
                    {STATUSES.map((s) => (
                      <button
                        key={s}
                        className={selected.status === s ? 'active' : ''}
                        disabled={saving || selected.status === s}
                        onClick={() => save({ status: s }, `Marked ${STATUS_LABELS[s]}`)}
                      >
                        <span className={`dot dot-${STATUS_DOT[s]}`} /> {STATUS_LABELS[s]}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Notes</div>
                  <div className="xp-section-hint">Only admins see these.</div>
                  <NotesBox
                    key={selected.id} saved={selected.admin_notes || ''} saving={saving}
                    onSave={(notes) => save({ admin_notes: notes }, 'Notes saved')}
                  />
                </div>
              </div>
            </>
          )}
        </section>
      </div>
    </div>
  );
}
