import { useEffect, useState } from 'react';
import { useApi, apiPost, mediaUrl } from '../api';
import { ClipboardCheckIcon, RefreshIcon } from '../components/Icons';
import { Toast } from '../components/Kit';
import { useToast } from '../hooks';
import { notifyVendorChangesChanged } from '../vendorChanges';

// What vendors change themselves waits here (services/vendor_review on the
// server): travellers keep seeing the live version until it is approved.
// Availability and Show/Hide never come here: vendors set those at once.

const FILTERS = [
  ['pending', 'Waiting'],
  ['changes_requested', 'Sent back'],
  ['open', 'All'],
];
const STATUS_LABELS = { pending: 'Waiting for review', changes_requested: 'Sent back to the vendor' };
const STATUS_DOT = { pending: 'new', changes_requested: 'hidden' };
const TZ = 'Asia/Colombo';

const CATEGORIES = {
  boat: 'Boat ride', water_sports: 'Water sports', guided_tour: 'Guided tour', wildlife: 'Wildlife',
  cultural: 'Cultural', adventure: 'Adventure', food: 'Food', other: 'Other',
};
const BASES = { per_person: '/ person', per_group: '/ group', per_hour: '/ hour' };

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

const formatDuration = (minutes) => {
  if (!minutes) return null;
  if (minutes < 60) return `${minutes} min`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
};

/** "LKR 30,000 / group · max 7" */
const optionLine = (o, currency) => {
  const amount = `${currency || ''} ${Number(o.amount).toLocaleString()}`.trim();
  const price = o.basis === 'from' ? `From ${amount}` : `${amount} ${BASES[o.basis] || ''}`.trim();
  const people = [o.min_people && `min ${o.min_people}`, o.max_people && `max ${o.max_people}`]
    .filter(Boolean).join(', ');
  const usd = o.usd != null ? ` ($${Number(o.usd).toLocaleString()})` : '';
  return `${price}${usd}${people ? ` · ${people}` : ''}`;
};

/** One value of a change, shown the way it reads in the app. */
function Value({ field, value, currency }) {
  const empty = value == null || value === '' || (Array.isArray(value) && value.length === 0);
  if (empty) return <span className="muted">—</span>;
  if (field === 'photo_urls' || field === 'logo_url') {
    const urls = Array.isArray(value) ? value : [value];
    return (
      <div className="vc-photos">
        {urls.map((url, i) => (
          <a key={`${url}-${i}`} href={mediaUrl(url)} target="_blank" rel="noreferrer" title="Open full size">
            <img src={mediaUrl(url)} alt="" />
          </a>
        ))}
      </div>
    );
  }
  if (field === 'price_options') {
    return <ul className="vc-list">{value.map((o, i) => <li key={o.id || i}>{optionLine(o, currency)}</li>)}</ul>;
  }
  if (field === 'category') return <span>{CATEGORIES[value] || value}</span>;
  if (field === 'duration_minutes') return <span>{formatDuration(value)}</span>;
  if (Array.isArray(value)) return <ul className="vc-list">{value.map((v, i) => <li key={i}>{String(v)}</li>)}</ul>;
  if (field === 'description') return <div className="quote vc-long">{value}</div>;
  return <span className="vc-text">{String(value)}</span>;
}

export default function VendorChanges() {
  const [filter, setFilter] = useState('pending');
  const [selected, setSelected] = useState(null);
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [toast, notify] = useToast(4000);

  const { data, error, refetch } = useApi(`/admin/experiences/changes?status=${filter}`);
  const items = data?.items || [];

  // Keep the open item in step with a refetch; drop it once it has left the list.
  useEffect(() => {
    if (!selected || !data) return;
    const fresh = items.find((i) => i.kind === selected.kind && i.id === selected.id);
    setSelected(fresh || null);
  }, [data]); // eslint-disable-line react-hooks/exhaustive-deps

  const open = (item) => {
    setSelected(item);
    setNote(item.review_status === 'changes_requested' ? item.review_note || '' : '');
  };

  const decide = async (decision) => {
    if (decision === 'request_changes' && !note.trim()) {
      notify('Write what the vendor should change first.', 'error');
      return;
    }
    const path = selected.kind === 'package'
      ? `/admin/experiences/packages/${selected.id}/review`
      : `/admin/experiences/vendors/${selected.id}/review`;
    setSaving(true);
    try {
      await apiPost(path, { decision, note: decision === 'approve' ? null : note.trim() });
      notify(decision === 'approve'
        ? `${selected.is_new ? 'Approved and published' : 'Approved and live'}. The vendor has been told.`
        : 'Sent back. The vendor gets your note by email and in the app.');
      setSelected(null);
      setNote('');
      refetch();
      notifyVendorChangesChanged();
    } catch (err) {
      notify(`Could not save the decision: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const currencyOf = (item) =>
    item.changes.find((c) => c.field === 'price_currency')?.after || item.price_currency;

  return (
    <div>
      <div className="xp-toolbar">
        <div className="seg">
          {FILTERS.map(([value, label]) => (
            <button
              key={value}
              className={`seg-btn ${filter === value ? 'active' : ''}`}
              onClick={() => { setFilter(value); setSelected(null); }}
            >
              {STATUS_DOT[value] && <span className={`dot dot-${STATUS_DOT[value]}`} />}
              {label}
              {value === 'pending' && data?.pending != null && filter === 'pending' && (
                <span className="seg-count">{data.pending}</span>
              )}
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
                <ClipboardCheckIcon size={32} />
                <strong>{filter === 'changes_requested' ? 'Nothing sent back' : 'All caught up'}</strong>
                {filter === 'changes_requested'
                  ? 'Edits you send back to a vendor wait here until they fix them.'
                  : 'New packages and edits vendors make in the partner portal or the app show here for approval.'}
              </div>
            )}

            {items.map((item) => (
              <button
                key={`${item.kind}-${item.id}`}
                className={`xp-row ${selected?.kind === item.kind && selected?.id === item.id ? 'active' : ''}`}
                onClick={() => open(item)}
                style={{ alignItems: 'flex-start' }}
              >
                <span
                  className={`dot dot-${STATUS_DOT[item.review_status]}`}
                  style={{ marginTop: 6 }} title={STATUS_LABELS[item.review_status]}
                />
                <div className="xp-row-main">
                  <div className="xp-row-title">{item.title}</div>
                  <div className="xp-row-sub" style={{ color: 'var(--text-primary)' }}>{item.vendor_name}</div>
                  <div className="xp-row-sub">{item.summary || 'Changes'}</div>
                </div>
                <div className="xp-row-side" title={formatDateTime(item.submitted_at)}>
                  {formatAge(item.submitted_at)}
                </div>
              </button>
            ))}
          </div>
        </aside>

        <section className="xp-pane xp-detail-pane">
          {!selected && (
            <div className="xp-empty">
              <ClipboardCheckIcon size={36} />
              <strong>Select a change</strong>
              Approve it to put it live, or send it back with a note saying what to fix.
            </div>
          )}

          {selected && (
            <>
              <div className="xp-detail-head">
                <div style={{ flex: 1, minWidth: 0 }}>
                  <button className="xp-back" onClick={() => setSelected(null)}>← All changes</button>
                  <div className="xp-detail-title">{selected.title}</div>
                  <div className="xp-detail-sub">
                    {selected.vendor_name} · {selected.kind === 'package' ? 'Package' : 'Business profile'}
                    {' · '}sent {formatDateTime(selected.submitted_at)}
                  </div>
                </div>
                <span className="status-label">
                  <span className={`dot dot-${STATUS_DOT[selected.review_status]}`} /> {STATUS_LABELS[selected.review_status]}
                </span>
              </div>

              <div className="xp-body">
                {selected.review_status === 'changes_requested' && (
                  <div className="xp-section">
                    <div className="xp-section-title">Sent back</div>
                    <div className="xp-section-hint">
                      {formatDateTime(selected.reviewed_at)}. Waiting for the vendor to update it.
                    </div>
                    <div className="quote">{selected.review_note}</div>
                  </div>
                )}

                <div className="xp-section">
                  <div className="xp-section-title">
                    {selected.is_new ? 'New package' : 'What changes'}
                  </div>
                  <div className="xp-section-hint">
                    {selected.is_new
                      ? 'Not visible to travellers until you approve it. It meets at the vendor’s address; set its own meeting point in Experiences if needed.'
                      : 'Travellers see “Now” until you approve.'}
                  </div>
                  <div className="vc-table">
                    {!selected.is_new && (
                      <div className="vc-row vc-head">
                        <div>Field</div><div>Now</div><div>Asked for</div>
                      </div>
                    )}
                    {selected.changes.map((c) => (
                      <div key={c.field} className={`vc-row ${selected.is_new ? 'vc-new' : ''}`}>
                        <div className="vc-field">{c.label}</div>
                        {!selected.is_new && (
                          <div className="vc-before">
                            <Value field={c.field} value={c.before} currency={selected.price_currency} />
                          </div>
                        )}
                        <div className="vc-after">
                          <Value field={c.field} value={c.after} currency={currencyOf(selected)} />
                        </div>
                      </div>
                    ))}
                    {selected.changes.length === 0 && (
                      <div className="muted" style={{ padding: '8px 0' }}>Nothing differs from what is live.</div>
                    )}
                  </div>
                </div>

                <div className="xp-section">
                  <div className="xp-section-title">Decision</div>
                  <div className="xp-section-hint">
                    The vendor is told either way, by email and in the app. To fix something small
                    yourself, edit it in Experiences, then approve.
                  </div>
                  <textarea
                    className="form-textarea" rows={3} value={note} maxLength={2000}
                    placeholder="What should the vendor change? e.g. Use a photo of the boat itself, not a stock image."
                    onChange={(e) => setNote(e.target.value)}
                  />
                  <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 10 }}>
                    <button
                      className="btn btn-danger-ghost btn-sm" disabled={saving}
                      onClick={() => decide('request_changes')}
                    >
                      {selected.review_status === 'changes_requested' ? 'Update the note' : 'Send back with note'}
                    </button>
                    <button
                      className="btn btn-primary btn-sm" disabled={saving}
                      onClick={() => {
                        const what = selected.is_new ? 'Publish this package' : 'Put these changes live';
                        if (confirm(`${what} for travellers?`)) decide('approve');
                      }}
                    >
                      {saving ? 'Saving…' : selected.is_new ? 'Approve and publish' : 'Approve'}
                    </button>
                  </div>
                </div>
              </div>
            </>
          )}
        </section>
      </div>

      <Toast toast={toast} />
    </div>
  );
}
