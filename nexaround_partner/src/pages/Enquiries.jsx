import { useEffect, useState } from 'react';
import { useApi, apiGet, apiPatch } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import {
  InboxIcon, SearchIcon, PhoneIcon, MailIcon, WhatsAppIcon, RefreshIcon, TicketIcon, UsersIcon, ClockIcon, EditIcon,
} from '../components/Icons';
import { Toast, Section, InfoTile, Avatar } from '../components/Kit';
import {
  ENQUIRY_STATUSES, STATUS_LABELS, STATUS_TONES, formatDateTime, formatAge, formatDay, guestsLabel, digitsOnly,
} from '../format';

const PAGE_SIZE = 50;

const whatsAppLink = (enquiry, vendorName) => {
  const greeting = `Hi ${enquiry.contact_name}, thanks for your enquiry`
    + (enquiry.package_title_snapshot ? ` about "${enquiry.package_title_snapshot}"` : '')
    + (vendorName ? `. This is ${vendorName}.` : '.');
  return `https://wa.me/${digitsOnly(enquiry.contact_phone)}?text=${encodeURIComponent(greeting)}`;
};

export default function Enquiries({ vendorName, initialId }) {
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState(null);
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const [counts, setCounts] = useState({});
  const [countsVersion, setCountsVersion] = useState(0);
  const [toast, setToast] = useState(null);

  const { data, error, refetch } = useApi(
    `/partner/enquiries?page=${page}&page_size=${PAGE_SIZE}${statusFilter ? `&status=${statusFilter}` : ''}`
  );
  const rawEnquiries = data?.enquiries || [];
  const totalPages = Math.max(1, Math.ceil((data?.total || 0) / PAGE_SIZE));

  // The list only returns one page, so per-status totals come from one
  // page_size=1 request per status.
  useEffect(() => {
    let active = true;
    Promise.all(
      ['', ...ENQUIRY_STATUSES].map((s) =>
        apiGet(`/partner/enquiries?page=1&page_size=1${s ? `&status=${s}` : ''}`)
          .then((res) => [s || 'all', res.total])
          .catch(() => [s || 'all', null])
      )
    ).then((pairs) => { if (active) setCounts(Object.fromEntries(pairs)); });
    return () => { active = false; };
  }, [countsVersion]);

  // Opened from the dashboard: select that enquiry once the first page lands.
  const [pendingId, setPendingId] = useState(initialId || null);
  if (pendingId && data) {
    const match = rawEnquiries.find((e) => e.id === pendingId);
    setPendingId(null);
    if (match) {
      setSelected(match);
      setNotes(match.vendor_notes || '');
    }
  }

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
    !q || [e.contact_name, e.contact_phone, e.contact_email, e.package_title_snapshot]
      .some((f) => (f || '').toLowerCase().includes(q))
  );

  const notesDirty = selected && notes !== (selected.vendor_notes || '');

  // A new enquiry, or a status changed in another tab, by another login or
  // by NexAround: the list and counts follow, and so does the open enquiry —
  // except a note the vendor is part-way through typing.
  useLiveEvent(['enquiry.created', 'enquiry.updated', RESYNC], ({ type, data }) => {
    refresh();
    if (type === 'enquiry.updated' && selected?.id === data.id) {
      setSelected((s) => ({ ...s, status: data.status, vendor_notes: data.vendor_notes }));
      if (!notesDirty) setNotes(data.vendor_notes || '');
    }
  });

  const open = (enquiry) => {
    if (notesDirty && !confirm('Discard your unsaved note?')) return;
    setSelected(enquiry);
    setNotes(enquiry.vendor_notes || '');
  };

  const close = () => {
    if (notesDirty && !confirm('Discard your unsaved note?')) return;
    setSelected(null);
  };

  const changeFilter = (status) => {
    setStatusFilter(status);
    setPage(1);
  };

  const patch = async (body, message) => {
    setBusy(true);
    try {
      const updated = await apiPatch(`/partner/enquiries/${selected.id}`, body);
      setSelected(updated);
      if ('vendor_notes' in body) setNotes(updated.vendor_notes || '');
      refresh();
      notify(message);
    } catch (err) {
      notify(`Could not save: ${err.message}`, 'error');
    } finally {
      setBusy(false);
    }
  };

  const filters = [['', 'All'], ...ENQUIRY_STATUSES.map((s) => [s, STATUS_LABELS[s]])];

  return (
    <>
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
            <input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, phone, package…" />
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
            {!data && !error && <div className="loader" />}

            {data && enquiries.length === 0 && (
              <div className="xp-empty">
                <InboxIcon size={32} />
                <strong>{search || statusFilter ? 'Nothing matches' : 'No enquiries yet'}</strong>
                {search || statusFilter
                  ? 'Try another status or search.'
                  : 'They arrive here as soon as a traveller asks about one of your packages.'}
              </div>
            )}

            {enquiries.map((e) => (
              <button
                key={e.id}
                className={`xp-row ${selected?.id === e.id ? 'active' : ''}`}
                onClick={() => open(e)}
                style={{ alignItems: 'flex-start' }}
              >
                <Avatar name={e.contact_name} />
                <div className="xp-row-main">
                  <div className={`xp-row-title ${e.status === 'new' ? 'strong' : ''}`}>{e.contact_name}</div>
                  <div className="xp-row-sub" style={{ color: 'var(--text-primary)' }}>
                    {e.package_title_snapshot || 'General enquiry'}
                  </div>
                  <div className="xp-row-sub">
                    {[guestsLabel(e.party_size), formatDay(e.preferred_date)].filter(Boolean).join(' · ') || 'No date or party size given'}
                  </div>
                </div>
                <div className="xp-row-side">
                  <span title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</span>
                  <span className={`pill tone-${STATUS_TONES[e.status] || 'gray'}`}>{STATUS_LABELS[e.status] || e.status}</span>
                </div>
              </button>
            ))}
          </div>

          {totalPages > 1 && (
            <div className="xp-list-foot">
              <button className="btn btn-ghost btn-sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>Previous</button>
              <span>Page {page} of {totalPages}</span>
              <button className="btn btn-ghost btn-sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>Next</button>
            </div>
          )}
        </aside>

        <section className="xp-pane xp-detail-pane">
          {!selected && (
            <div className="xp-empty">
              <InboxIcon size={36} />
              <strong>Select an enquiry</strong>
              {counts.new
                ? `${counts.new} new ${counts.new === 1 ? 'enquiry is' : 'enquiries are'} waiting for your reply.`
                : 'The traveller’s request and contact details open here.'}
            </div>
          )}

          {selected && (
            <>
              <div className="xp-detail-head">
                <Avatar name={selected.contact_name} size="lg" />
                <div style={{ flex: 1, minWidth: 0 }}>
                  <button className="xp-back" onClick={close}>← All enquiries</button>
                  <div className="xp-detail-title">{selected.contact_name}</div>
                  <div className="xp-detail-sub">Received {formatDateTime(selected.created_at)}</div>
                </div>
                <span className={`pill tone-${STATUS_TONES[selected.status] || 'gray'}`}>
                  {STATUS_LABELS[selected.status] || selected.status}
                </span>
              </div>

              <div className="xp-body">
                {/* The whole job: get the vendor talking to the traveller. */}
                <div className="xp-section">
                  <div className="contact-card tone-green">
                    <div className="contact-card-lines">
                      {selected.contact_phone}
                      {selected.contact_email && <div><span>{selected.contact_email}</span></div>}
                    </div>
                    <div className="contact-card-actions">
                      <a className="btn btn-whatsapp btn-sm" href={whatsAppLink(selected, vendorName)} target="_blank" rel="noreferrer">
                        <WhatsAppIcon size={15} /> WhatsApp
                      </a>
                      <a className="btn btn-ghost btn-sm" href={`tel:${selected.contact_phone}`}>
                        <PhoneIcon size={14} /> Call
                      </a>
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
                  <div className="info-grid">
                    <InfoTile
                      tone="teal" icon={TicketIcon} label="Package"
                      value={selected.package_title_snapshot || 'General enquiry'}
                    />
                    <InfoTile
                      tone="blue" icon={UsersIcon} label="Party size"
                      value={guestsLabel(selected.party_size) || 'Not given'} muted={!selected.party_size}
                    />
                    <InfoTile
                      tone="amber" icon={ClockIcon} label="Preferred date"
                      value={formatDay(selected.preferred_date) || 'Flexible'} muted={!selected.preferred_date}
                    />
                  </div>
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
                    {ENQUIRY_STATUSES.map((s) => (
                      <button
                        key={s}
                        className={`tone-${STATUS_TONES[s]} ${selected.status === s ? 'active' : ''}`}
                        disabled={busy || selected.status === s}
                        onClick={() => patch({ status: s }, `Marked as ${STATUS_LABELS[s].toLowerCase()}`)}
                      >
                        <span className={`dot dot-${s}`} /> {STATUS_LABELS[s]}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="xp-section">
                  <Section tone="amber" icon={EditIcon} title="Your notes" hint="Only you and NexAround see these.">
                    <div className="form-group">
                      <textarea
                        className="form-textarea" rows={4} value={notes}
                        placeholder="e.g. Quoted LKR 30,000 for 4, waiting to hear back"
                        onChange={(e) => setNotes(e.target.value)}
                      />
                      <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 10 }}>
                        {notesDirty && (
                          <button className="btn btn-ghost btn-sm" onClick={() => setNotes(selected.vendor_notes || '')}>Discard</button>
                        )}
                        <button
                          className="btn btn-primary btn-sm"
                          disabled={!notesDirty || busy}
                          onClick={() => patch({ vendor_notes: notes }, 'Note saved')}
                        >
                          {busy ? 'Saving…' : 'Save note'}
                        </button>
                      </div>
                    </div>
                  </Section>
                </div>
              </div>
            </>
          )}
        </section>
      </div>

      <Toast toast={toast} />
    </>
  );
}
