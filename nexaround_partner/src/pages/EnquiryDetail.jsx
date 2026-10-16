import { useState } from 'react';
import { useApi, apiPatch } from '../api';
import { useAuth } from '../auth';
import { RESYNC, useLiveEvent } from '../live';
import { useToast } from '../toast';
import { useUnsavedGuard } from '../hooks';
import {
  InboxIcon, PhoneIcon, MailIcon, WhatsAppIcon, TicketIcon, UsersIcon, ClockIcon, EditIcon,
  MapPinIcon, ClipboardCheckIcon,
} from '../components/Icons';
import { Section, InfoTile, Avatar } from '../components/Kit';
import { EmptyState, EnquiryStatusPill, Loader } from '../components/Lists';
import { Field } from '../components/Forms';
import {
  CANCELLED_STATUSES, STATUS_LABELS, STATUS_TONES, VENDOR_STATUSES, formatDateTime, formatDay,
  freeCancellationLastDay, guestsLabel, digitsOnly,
} from '../format';

const whatsAppLink = (enquiry, vendorName) => {
  const greeting = `Hi ${enquiry.contact_name}, thanks for your enquiry`
    + (enquiry.package_title_snapshot ? ` about "${enquiry.package_title_snapshot}"` : '')
    + (vendorName ? `. This is ${vendorName}.` : '.');
  return `https://wa.me/${digitsOnly(enquiry.contact_phone)}?text=${encodeURIComponent(greeting)}`;
};

/**
 * One enquiry, loaded by its own id so a link to it works whichever page of
 * the list it is on. The parent keys this by id, so opening another enquiry
 * starts clean: no note carried over, no stale status.
 */
/** A cancelled request: who, when, why, and whether it was late. Final. */
function CancelledNote({ enquiry }) {
  const byTraveller = enquiry.status === 'customer_cancelled';
  return (
    <div className="booking-note cancelled">
      {byTraveller
        ? <>The traveller cancelled this {enquiry.confirmed_date ? 'booking' : 'request'} on <strong>{formatDateTime(enquiry.cancelled_at)}</strong>.</>
        : <>You cancelled this on <strong>{formatDateTime(enquiry.cancelled_at)}</strong>.</>}
      {enquiry.cancellation_reason && <div style={{ marginTop: 6 }}>Reason: {enquiry.cancellation_reason}</div>}
      {byTraveller && enquiry.late_cancellation && (
        <div className="late">
          Late cancellation: less than 72 hours before {formatDay(enquiry.confirmed_date)}. Under the booking
          terms the traveller may have to pay the booking price.
        </div>
      )}
      <div className="form-hint" style={{ marginTop: 8 }}>
        A cancelled request cannot be reopened. Contact NexAround if this was a mistake.
      </div>
    </div>
  );
}

export default function EnquiryDetail({ id, onClose, onChanged }) {
  const { me } = useAuth();
  const notify = useToast();
  const { data, error } = useApi(`/partner/enquiries/${id}`);
  // The newest copy from a save or a live event; falls back to what loaded.
  const [latest, setLatest] = useState(null);
  // null until the vendor types, so the box follows the server until then.
  const [draft, setDraft] = useState(null);
  const [busy, setBusy] = useState(false);
  // 'confirm' or 'cancel' while that form is open: both need more than a click.
  const [mode, setMode] = useState(null);
  const [confirmDate, setConfirmDate] = useState('');
  const [reason, setReason] = useState('');

  const enquiry = latest || data;
  const savedNote = enquiry?.vendor_notes || '';
  const notes = draft ?? savedNote;
  const notesDirty = draft !== null && draft !== savedNote;

  useUnsavedGuard(notesDirty, {
    message: 'You have a note that has not been saved. It will be lost.',
  });

  // Changed in another tab, by another login or by NexAround: follow it,
  // except a note the vendor is part-way through typing (draft is kept).
  useLiveEvent(['enquiry.updated', RESYNC], ({ type, data: update }) => {
    if (type === 'enquiry.updated' && update.id === id) {
      // Includes the booking: a traveller cancelling shows up here live.
      setLatest((prev) => ({ ...(prev || data), ...update }));
    }
  });

  const patch = async (body, message) => {
    setBusy(true);
    try {
      const updated = await apiPatch(`/partner/enquiries/${id}`, body);
      setLatest(updated);
      if ('vendor_notes' in body) setDraft(null);
      setMode(null);
      onChanged();
      notify(message);
    } catch (err) {
      notify(`Could not save: ${err.message}`, 'error');
    } finally {
      setBusy(false);
    }
  };

  if (error && !enquiry) {
    return (
      <EmptyState icon={InboxIcon} title="Enquiry not found">
        It may have been removed, or it belongs to another account.
        <button type="button" className="btn btn-ghost btn-sm" style={{ marginTop: 12 }} onClick={onClose}>
          Back to all enquiries
        </button>
      </EmptyState>
    );
  }
  if (!enquiry) return <div className="xp-body"><Loader /></div>;

  return (
    <>
      <div className="xp-detail-head">
        <Avatar name={enquiry.contact_name} size="lg" />
        <div style={{ flex: 1, minWidth: 0 }}>
          <button className="xp-back" onClick={onClose}>← All enquiries</button>
          <div className="xp-detail-title">{enquiry.contact_name}</div>
          <div className="xp-detail-sub">Received {formatDateTime(enquiry.created_at)}</div>
        </div>
        <EnquiryStatusPill status={enquiry.status} />
      </div>

      <div className="xp-body">
        {/* The whole job: get the vendor talking to the traveller. */}
        <div className="xp-section">
          <div className="contact-card tone-green">
            <div className="contact-card-lines">
              {enquiry.contact_phone}
              {enquiry.contact_email && <div><span>{enquiry.contact_email}</span></div>}
            </div>
            <div className="contact-card-actions">
              <a className="btn btn-whatsapp btn-sm" href={whatsAppLink(enquiry, me?.vendor_name)} target="_blank" rel="noreferrer">
                <WhatsAppIcon size={15} /> WhatsApp
              </a>
              <a className="btn btn-ghost btn-sm" href={`tel:${enquiry.contact_phone}`}>
                <PhoneIcon size={14} /> Call
              </a>
              {enquiry.contact_email && (
                <a className="btn btn-ghost btn-sm" href={`mailto:${enquiry.contact_email}`}>
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
              value={enquiry.package_title_snapshot || 'General enquiry'}
            />
            <InfoTile
              tone="blue" icon={UsersIcon} label="Party size"
              value={guestsLabel(enquiry.party_size) || 'Not given'} muted={!enquiry.party_size}
            />
            <InfoTile
              tone="amber" icon={ClockIcon} label="Preferred date"
              value={formatDay(enquiry.preferred_date) || 'Flexible'} muted={!enquiry.preferred_date}
            />
            <InfoTile
              tone="green" icon={MapPinIcon} label="Pickup"
              value={enquiry.pickup_location || 'Not given'} muted={!enquiry.pickup_location}
            />
            {/* So the vendor can point to the payment and 72-hour rules the
                traveller agreed to. Older requests carry no version. */}
            <InfoTile
              tone="teal" icon={ClipboardCheckIcon} label="Booking terms"
              value={enquiry.terms_version
                ? `Accepted version ${enquiry.terms_version} · ${formatDateTime(enquiry.terms_accepted_at)}`
                : 'Not recorded'}
              muted={!enquiry.terms_version}
            />
          </div>
          {enquiry.message && (
            <div style={{ marginTop: 18 }}>
              <div className="dl-label">Message</div>
              <div className="quote">{enquiry.message}</div>
            </div>
          )}
        </div>

        <div className="xp-section">
          <div className="xp-section-title">Status</div>
          {CANCELLED_STATUSES.includes(enquiry.status) ? (
            <CancelledNote enquiry={enquiry} />
          ) : (
            <>
              <div className="xp-section-hint">
                Confirming or cancelling notifies the traveller. Other changes save immediately.
              </div>
              <div className="status-seg">
                {VENDOR_STATUSES.map((s) => (
                  <button
                    key={s}
                    className={`tone-${STATUS_TONES[s]} ${enquiry.status === s ? 'active' : ''}`}
                    disabled={busy || (enquiry.status === s && s !== 'confirmed')}
                    onClick={() => {
                      if (s === 'confirmed') {
                        setConfirmDate(enquiry.confirmed_date || enquiry.preferred_date || '');
                        setMode('confirm');
                      } else if (s === 'provider_cancelled') {
                        setReason('');
                        setMode('cancel');
                      } else {
                        patch({ status: s }, `Marked as ${STATUS_LABELS[s].toLowerCase()}`);
                      }
                    }}
                  >
                    <span className={`dot dot-${s}`} />{' '}
                    {s === 'confirmed' && enquiry.status === 'confirmed' ? 'Change date' : STATUS_LABELS[s]}
                  </button>
                ))}
              </div>

              {mode === 'confirm' && (
                <div className="booking-form">
                  <label className="form-label" htmlFor="confirm-date">Date agreed with the traveller</label>
                  <input
                    id="confirm-date" type="date" className="form-input" value={confirmDate}
                    onChange={(e) => setConfirmDate(e.target.value)}
                  />
                  {confirmDate && (
                    <div className="form-hint">
                      The traveller is notified, and can cancel for free until the end of{' '}
                      {formatDay(freeCancellationLastDay(confirmDate))}.
                    </div>
                  )}
                  <div className="booking-form-actions">
                    <button className="btn btn-ghost btn-sm" onClick={() => setMode(null)}>Back</button>
                    <button
                      className="btn btn-primary btn-sm" disabled={busy || !confirmDate}
                      onClick={() => patch(
                        { status: 'confirmed', confirmed_date: confirmDate },
                        'Booking confirmed. The traveller has been notified.',
                      )}
                    >
                      {busy ? 'Saving…' : 'Confirm booking'}
                    </button>
                  </div>
                </div>
              )}

              {mode === 'cancel' && (
                <div className="booking-form">
                  <label className="form-label" htmlFor="cancel-reason">Reason (shown to the traveller)</label>
                  <textarea
                    id="cancel-reason" className="form-textarea" rows={3} value={reason} maxLength={1000}
                    placeholder="e.g. The boat is under repair that week"
                    onChange={(e) => setReason(e.target.value)}
                  />
                  <div className="form-hint">
                    The traveller is notified. A cancellation cannot be undone, and you must arrange any
                    refund or rescheduling.
                  </div>
                  <div className="booking-form-actions">
                    <button className="btn btn-ghost btn-sm" onClick={() => setMode(null)}>Back</button>
                    <button
                      className="btn btn-danger btn-sm" disabled={busy}
                      onClick={() => patch(
                        { status: 'provider_cancelled', cancellation_reason: reason },
                        'Cancelled. The traveller has been notified.',
                      )}
                    >
                      {busy ? 'Saving…' : `Cancel this ${enquiry.status === 'confirmed' ? 'booking' : 'request'}`}
                    </button>
                  </div>
                </div>
              )}

              {enquiry.status === 'confirmed' && mode !== 'confirm' && (
                <div className="booking-note">
                  Confirmed for <strong>{formatDay(enquiry.confirmed_date)}</strong>. The traveller can
                  cancel for free until the end of {formatDay(enquiry.free_cancellation_last_day)};
                  after that they may have to pay the booking price.
                </div>
              )}
            </>
          )}
        </div>

        <div className="xp-section">
          <Section tone="amber" icon={EditIcon} title="Your notes" hint="Only you and NexAround see these.">
            <Field>
              <textarea
                className="form-textarea" rows={4} value={notes}
                placeholder="e.g. Quoted LKR 30,000 for 4, waiting to hear back"
                onChange={(e) => setDraft(e.target.value)}
              />
              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 10 }}>
                {notesDirty && (
                  <button className="btn btn-ghost btn-sm" onClick={() => setDraft(null)}>Discard</button>
                )}
                <button
                  className="btn btn-primary btn-sm"
                  disabled={!notesDirty || busy}
                  onClick={() => patch({ vendor_notes: draft }, 'Note saved')}
                >
                  {busy ? 'Saving…' : 'Save note'}
                </button>
              </div>
            </Field>
          </Section>
        </div>
      </div>
    </>
  );
}
