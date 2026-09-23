import { useEffect, useState } from 'react';
import { useApi, apiGet, apiPatch } from '../api';
import {
  InboxIcon, SearchIcon, PhoneIcon, MailIcon, WhatsAppIcon, RefreshIcon,
} from '../components/Icons';

const PAGE_SIZE = 50;
const STATUSES = ['new', 'contacted', 'closed', 'spam'];
const STATUS_LABELS = { new: 'New', contacted: 'Contacted', closed: 'Closed', spam: 'Spam' };

const TZ = 'Asia/Colombo';

const formatDateTime = (value) =>
  value
    ? new Date(value).toLocaleString('en-GB', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
    })
    : '—';

// Short age for the list: "5m", "3h", "2d", then a date.
const formatAge = (value) => {
  const minutes = Math.floor((Date.now() - new Date(value).getTime()) / 60000);
  if (minutes < 1) return 'now';
  if (minutes < 60) return `${minutes}m`;
  if (minutes < 60 * 24) return `${Math.floor(minutes / 60)}h`;
  if (minutes < 60 * 24 * 7) return `${Math.floor(minutes / 1440)}d`;
  return new Date(value).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: TZ });
};

// preferred_date is a plain YYYY-MM-DD; parse it as a calendar date, not UTC midnight.
const formatDay = (value) => {
  if (!value) return null;
  const [y, m, d] = value.split('-').map(Number);
  return new Date(y, m - 1, d).toLocaleDateString('en-GB', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
  });
};

const digitsOnly = (phone) => (phone || '').replace(/[^0-9]/g, '');

const whatsAppLink = (enquiry) => {
  const greeting = `Hi ${enquiry.contact_name}, thanks for your enquiry`
    + (enquiry.package_title_snapshot ? ` about "${enquiry.package_title_snapshot}"` : '')
    + ' on nexARound.';
  return `https://wa.me/${digitsOnly(enquiry.contact_phone)}?text=${encodeURIComponent(greeting)}`;
};

export default function ExperienceEnquiries() {
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState(null);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [counts, setCounts] = useState({});
  const [countsVersion, setCountsVersion] = useState(0);
  const [toast, setToast] = useState(null);

  const { data, error, refetch } = useApi(
    `/admin/experiences/enquiries?page=${page}&page_size=${PAGE_SIZE}`
    + (statusFilter ? `&status=${statusFilter}` : '')
  );

  const rawEnquiries = data?.enquiries || [];
  const total = data?.total || 0;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  // The list endpoint only returns the page it was asked for, so per-status
  // totals come from one page_size=1 request per status.
  useEffect(() => {
    let active = true;
    Promise.all(
      ['', ...STATUSES].map((s) =>
        apiGet(`/admin/experiences/enquiries?page=1&page_size=1${s ? `&status=${s}` : ''}`)
          .then((res) => [s || 'all', res.total])
          .catch(() => [s || 'all', null])
      )
    ).then((pairs) => { if (active) setCounts(Object.fromEntries(pairs)); });
    return () => { active = false; };
  }, [countsVersion]);

  const refresh = () => {
    refetch();
    setCountsVersion((n) => n + 1);
  };

  const notify = (message, tone = 'ok') => {
    setToast({ message, tone });
    setTimeout(() => setToast(null), 3000);
  };

  // Search only narrows the page already loaded.
  const q = search.trim().toLowerCase();
  const enquiries = rawEnquiries.filter((e) =>
    !q || [e.contact_name, e.contact_phone, e.contact_email, e.package_title_snapshot, e.vendor_name_snapshot]
      .some((f) => (f || '').toLowerCase().includes(q))
  );

  const notesDirty = selected && notes !== (selected.admin_notes || '');

  const open = (enquiry) => {
    if (notesDirty && !confirm('Discard the unsaved note?')) return;
    setSelected(enquiry);
    setNotes(enquiry.admin_notes || '');
  };

  const close = () => {
    if (notesDirty && !confirm('Discard the unsaved note?')) return;
    setSelected(null);
  };

  const changeFilter = (status) => {
    setStatusFilter(status);
    setPage(1);
  };

  const update = async (patch, message) => {
    setSaving(true);
    try {
      const updated = await apiPatch(`/admin/experiences/enquiries/${selected.id}`, patch);
      setSelected(updated);
      if ('admin_notes' in patch) setNotes(updated.admin_notes || '');
      refresh();
      notify(message);
    } catch (err) {
      notify(`Could not update enquiry: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const filters = [['', 'All'], ...STATUSES.map((s) => [s, STATUS_LABELS[s]])];

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {filters.map(([value, label]) => (
            <button
              key={value || 'all'}
              className={`seg-btn ${statusFilter === value ? 'active' : ''}`}
              onClick={() => changeFilter(value)}
            >
              {value && <span className={`dot dot-${value}`} />}
              {label}
              {counts[value || 'all'] != null && <span className="seg-count">{counts[value || 'all']}</span>}
            </button>
          ))}
        </div>

        <div className="xp-toolbar-right">
          <div className="search-bar">
            <SearchIcon size={16} />
            <input
              type="text" value={search} onChange={(e) => setSearch(e.target.value)}
              placeholder="Search name, phone, vendor…"
            />
          </div>
          <button className="btn btn-ghost btn-sm" onClick={refresh} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      {error && <div className="login-error">{error}</div>}

      <div className={`xp-split ${selected ? 'has-selection' : ''}`}>
        <aside className="xp-pane xp-list-pane">
          <div className="xp-list-body">
            {!data && <div className="loader" />}

            {data && enquiries.length === 0 && (
              <div className="xp-empty">
                <InboxIcon size={32} />
                <strong>{search || statusFilter ? 'Nothing matches' : 'No enquiries yet'}</strong>
                {search || statusFilter
                  ? 'Try another status or search.'
                  : 'They appear here as soon as a traveller asks about a package in the app.'}
              </div>
            )}

            {enquiries.map((e) => (
              <button
                key={e.id}
                className={`xp-row ${selected?.id === e.id ? 'active' : ''}`}
                onClick={() => open(e)}
                style={{ alignItems: 'flex-start' }}
              >
                <span className={`dot dot-${e.status}`} style={{ marginTop: 6 }} title={STATUS_LABELS[e.status]} />
                <div className="xp-row-main">
                  <div className={`xp-row-title ${e.status === 'new' ? 'strong' : ''}`}>{e.contact_name}</div>
                  <div className="xp-row-sub" style={{ color: 'var(--text-primary)' }}>
                    {e.package_title_snapshot || 'General enquiry'}
                  </div>
                  <div className="xp-row-sub">
                    {[
                      e.vendor_name_snapshot,
                      e.party_size ? `${e.party_size} ${e.party_size === 1 ? 'guest' : 'guests'}` : null,
                      e.preferred_date ? formatDay(e.preferred_date) : null,
                    ].filter(Boolean).join(' · ')}
                  </div>
                </div>
                <div className="xp-row-side" title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</div>
              </button>
            ))}
          </div>

          {totalPages > 1 && (
            <div className="xp-list-foot">
              <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                Previous
              </button>
              <span>Page {page} of {totalPages}</span>
              <button className="btn btn-ghost btn-sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
                Next
              </button>
            </div>
          )}
        </aside>

        <section className="xp-pane xp-detail-pane">
          {!selected && (
            <div className="xp-empty">
              <InboxIcon size={36} />
              <strong>Select an enquiry</strong>
              {counts.new ? `${counts.new} new ${counts.new === 1 ? 'enquiry is' : 'enquiries are'} waiting for a reply.` : 'The traveller’s request and contact details open here.'}
            </div>
          )}

          {selected && (
            <>
              <div className="xp-detail-head">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <button className="xp-back" onClick={close}>← All enquiries</button>
                  <div className="xp-detail-title">{selected.contact_name}</div>
                  <div className="xp-detail-sub">Received {formatDateTime(selected.created_at)}</div>
                </div>
                <span className="status-label">
                  <span className={`dot dot-${selected.status}`} /> {STATUS_LABELS[selected.status] || selected.status}
                </span>
              </div>

              <div className="xp-body">
                <div className="xp-section">
                  <div className="contact-card">
                    <div className="contact-card-lines">
                      {selected.contact_phone}
                      {selected.contact_email && <div><span>{selected.contact_email}</span></div>}
                    </div>
                    <div className="contact-card-actions">
                      {selected.contact_phone && (
                        <>
                          <a className="btn btn-whatsapp btn-sm" href={whatsAppLink(selected)} target="_blank" rel="noreferrer">
                            <WhatsAppIcon size={15} /> WhatsApp
                          </a>
                          <a className="btn btn-ghost btn-sm" href={`tel:${selected.contact_phone}`}>
                            <PhoneIcon size={14} /> Call
                          </a>
                        </>
                      )}
                      {selected.contact_email && (
                        <a className="btn btn-ghost btn-sm" href={`mailto:${selected.contact_email}`}>
                          <MailIcon size={14} /> Email
                        </a>
                      )}
                    </div>
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title" style={{ marginBottom: 14 }}>Request</div>
                  <dl className="dl-grid">
                    <div>
                      <dt>Experience</dt>
                      <dd>{selected.package_title_snapshot || 'General enquiry'}</dd>
                    </div>
                    <div>
                      <dt>Vendor</dt>
                      <dd>{selected.vendor_name_snapshot || '—'}</dd>
                    </div>
                    <div>
                      <dt>Party size</dt>
                      <dd className={selected.party_size ? '' : 'muted'}>
                        {selected.party_size ? `${selected.party_size} ${selected.party_size === 1 ? 'guest' : 'guests'}` : 'Not given'}
                      </dd>
                    </div>
                    <div>
                      <dt>Preferred date</dt>
                      <dd className={selected.preferred_date ? '' : 'muted'}>
                        {formatDay(selected.preferred_date) || 'Flexible'}
                      </dd>
                    </div>
                  </dl>
                  {selected.message && (
                    <div style={{ marginTop: 18 }}>
                      <div className="dl-label">Message</div>
                      <div className="quote">{selected.message}</div>
                    </div>
                  )}
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Status</div>
                  <div className="xp-section-hint">Changes save immediately.</div>
                  <div className="status-seg">
                    {STATUSES.map((s) => (
                      <button
                        key={s}
                        className={selected.status === s ? 'active' : ''}
                        disabled={saving || selected.status === s}
                        onClick={() => update({ status: s }, `Marked as ${STATUS_LABELS[s].toLowerCase()}`)}
                      >
                        <span className={`dot dot-${s}`} /> {STATUS_LABELS[s]}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Internal notes</div>
                  <div className="xp-section-hint">Only admins see these.</div>
                  <textarea
                    className="form-textarea" rows={4} value={notes}
                    placeholder="e.g. Called on WhatsApp, quoted LKR 30,000 for 4"
                    onChange={(e) => setNotes(e.target.value)}
                  />
                  <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 10 }}>
                    {notesDirty && (
                      <button className="btn btn-ghost btn-sm" onClick={() => setNotes(selected.admin_notes || '')}>
                        Discard
                      </button>
                    )}
                    <button
                      className="btn btn-primary btn-sm"
                      disabled={!notesDirty || saving}
                      onClick={() => update({ admin_notes: notes }, 'Note saved')}
                    >
                      {saving ? 'Saving…' : 'Save note'}
                    </button>
                  </div>
                </div>
              </div>
            </>
          )}
        </section>
      </div>

      {toast && <div className={`xp-toast ${toast.tone === 'error' ? 'error' : ''}`}>{toast.message}</div>}
    </div>
  );
}
