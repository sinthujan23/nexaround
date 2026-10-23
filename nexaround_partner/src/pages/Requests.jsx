import { useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { useApi, apiPost } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import { InboxIcon, RefreshIcon } from '../components/Icons';
import { EmptyState, ErrorBanner, Loader, Pagination, StatusPill, Tabs } from '../components/Lists';
import { formatDateTime } from '../format';
import { useConfirm } from '../confirm';
import { useToast } from '../toast';

const PAGE_SIZE = 25;

// Why the vendor cannot do the date asked: the server's
// enquiry_lifecycle.DECLINE_REASONS. Only the label reaches the traveller.
const REASONS = [
  ['fully_booked', 'Fully booked that day'],
  ['weather', 'Weather or sea conditions'],
  ['not_running', 'Not running that day'],
  ['other', 'Other reason'],
];

const TODAY = () => new Date().toISOString().slice(0, 10);

/** "Sun 25 Oct 2026" from "2026-10-25". */
const formatDay = (value) => {
  if (!value) return '';
  const [y, m, d] = value.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-GB', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC',
  });
};

/** Where a request stands, as the vendor reads it. */
function standing(r) {
  if (r.status === 'confirmed') return { label: `Confirmed for ${formatDay(r.confirmed_date)}`, tone: 'green' };
  if (r.status === 'customer_cancelled') {
    return {
      label: r.offer_response === 'declined' ? 'The traveller declined your date' : 'Cancelled by the traveller',
      tone: 'gray',
    };
  }
  if (r.status === 'provider_cancelled') return { label: 'Cancelled by you', tone: 'gray' };
  if (r.status === 'closed') return { label: 'Closed', tone: 'gray' };
  if (r.vendor_response === 'other_date') {
    return { label: `You offered ${formatDay(r.vendor_offered_date)} · waiting for the traveller`, tone: 'amber' };
  }
  return { label: 'Waiting for your answer', tone: 'rose' };
}

/** One request: what was asked, and the answers when it is still open. */
function RequestCard({ request, onAnswered, highlight }) {
  const notify = useToast();
  const confirmDialog = useConfirm();
  const flexible = !request.preferred_date;
  const [mode, setMode] = useState(null); // null | 'confirm' | 'decline'
  const [day, setDay] = useState('');
  const [declineAs, setDeclineAs] = useState('other_date');
  const [reason, setReason] = useState('');
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const state = standing(request);

  const send = async (body, done) => {
    setSaving(true);
    try {
      const updated = await apiPost(`/partner/requests/${request.id}/answer`, body);
      onAnswered(updated);
      setMode(null);
      notify(done);
    } catch (err) {
      notify(`Could not send your answer: ${err.message}`, 'error');
    } finally {
      setSaving(false);
    }
  };

  const confirmNow = async () => {
    const when = flexible ? day : request.preferred_date;
    const ok = await confirmDialog({
      title: `Confirm for ${formatDay(when)}?`,
      message: `${request.party_size ? `${request.party_size} guests. ` : ''}The traveller is told at once by NexAround.`,
      confirmLabel: 'Confirm booking',
    });
    if (ok) send({ action: 'confirmed', day: flexible ? day : null }, 'Confirmed. The traveller has been told.');
  };

  const decline = async () => {
    if (declineAs === 'cancelled') {
      const ok = await confirmDialog({
        title: 'Cancel this request?',
        message: 'The traveller is told you cannot do it. This cannot be undone.',
        confirmLabel: 'Cancel request',
        danger: true,
      });
      if (!ok) return;
    }
    send(
      { action: declineAs, day: declineAs === 'other_date' ? day : null, reason, note: note.trim() || null },
      declineAs === 'other_date'
        ? 'Sent. The traveller will accept or decline the new date.'
        : 'Cancelled. The traveller has been told.',
    );
  };

  return (
    <div className={`xp-section rq-card ${highlight ? 'rq-highlight' : ''}`}>
      <div className="rq-head">
        <div style={{ minWidth: 0 }}>
          <strong className="rq-title">{request.package_title}</strong>
          <div className="muted">{request.reference} · received {formatDateTime(request.created_at)}</div>
        </div>
        <StatusPill tone={state.tone}>{state.label}</StatusPill>
      </div>

      <dl className="rq-facts">
        <div><dt>Date</dt><dd>{flexible ? 'Flexible: you choose' : formatDay(request.preferred_date)}</dd></div>
        <div><dt>Guests</dt><dd>{request.party_size || '—'}</dd></div>
        <div><dt>Price</dt><dd>{request.price_label || 'On request'}</dd></div>
      </dl>

      {request.can_answer && mode === null && (
        <div className="rv-actions">
          <span className="muted">NexAround arranges the booking with the traveller.</span>
          <button className="btn btn-ghost btn-sm" onClick={() => { setMode('decline'); setDay(''); }}>
            Can’t do this date
          </button>
          <button
            className="btn btn-primary btn-sm"
            onClick={() => (flexible ? setMode('confirm') : confirmNow())}
          >
            Confirm
          </button>
        </div>
      )}

      {mode === 'confirm' && (
        <div className="rq-form">
          <label className="form-label" htmlFor={`day-${request.id}`}>The day you can do it</label>
          <input
            id={`day-${request.id}`} type="date" className="form-input" min={TODAY()}
            value={day} onChange={(e) => setDay(e.target.value)}
          />
          <div className="rv-actions">
            <button className="btn btn-ghost btn-sm" onClick={() => setMode(null)}>Back</button>
            <button className="btn btn-primary btn-sm" disabled={!day || saving} onClick={confirmNow}>
              {saving ? 'Sending…' : 'Confirm'}
            </button>
          </div>
        </div>
      )}

      {mode === 'decline' && (
        <div className="rq-form">
          <div className="rq-choice">
            <label>
              <input
                type="radio" checked={declineAs === 'other_date'}
                onChange={() => setDeclineAs('other_date')}
              />
              Offer another date
            </label>
            <label>
              <input
                type="radio" checked={declineAs === 'cancelled'}
                onChange={() => setDeclineAs('cancelled')}
              />
              No other date: cancel
            </label>
          </div>
          {declineAs === 'other_date' && (
            <>
              <label className="form-label" htmlFor={`other-${request.id}`}>The date you can offer</label>
              <input
                id={`other-${request.id}`} type="date" className="form-input" min={TODAY()}
                value={day} onChange={(e) => setDay(e.target.value)}
              />
            </>
          )}
          <label className="form-label" htmlFor={`reason-${request.id}`}>Why not the date asked?</label>
          <select
            id={`reason-${request.id}`} className="form-select" value={reason}
            onChange={(e) => setReason(e.target.value)}
          >
            <option value="">Choose a reason</option>
            {REASONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select>
          <label className="form-label" htmlFor={`note-${request.id}`}>Note to NexAround (optional)</label>
          <textarea
            id={`note-${request.id}`} className="form-textarea" rows={2} maxLength={1000}
            placeholder="e.g. Mornings only that week. Only NexAround sees this."
            value={note} onChange={(e) => setNote(e.target.value)}
          />
          <div className="rv-actions">
            <span className="muted">
              {declineAs === 'other_date'
                ? 'The traveller accepts or declines the new date in the NexAround app.'
                : 'The traveller sees only the reason.'}
            </span>
            <button className="btn btn-ghost btn-sm" onClick={() => setMode(null)}>Back</button>
            <button
              className={`btn btn-sm ${declineAs === 'cancelled' ? 'btn-danger' : 'btn-primary'}`}
              disabled={saving || !reason || (declineAs === 'other_date' && !day)}
              onClick={decline}
            >
              {saving ? 'Sending…' : declineAs === 'other_date' ? 'Send to NexAround' : 'Cancel request'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/**
 * Travellers' requests for this vendor's packages: the package, date, guests
 * and price - never who asked. "To answer" is the to-do list, oldest first.
 * /requests/:requestId (a notification or email) shows that one first.
 */
export default function Requests() {
  const { requestId } = useParams();
  const [params, setParams] = useSearchParams();
  const all = params.get('filter') === 'all';
  const page = Math.max(1, Number(params.get('page')) || 1);

  const { data, error, refetch } = useApi(
    `/partner/requests?scope=${all ? 'all' : 'open'}&page=${page}&page_size=${PAGE_SIZE}`
  );
  const single = useApi(requestId ? `/partner/requests/${requestId}` : null);
  const [answered, setAnswered] = useState({});

  // A new request, or NexAround or the traveller changing one, shows at once.
  useLiveEvent(['requests.changed', 'activity.created', RESYNC], () => {
    refetch();
    if (requestId) single.refetch();
  });

  const onAnswered = (updated) => {
    setAnswered((s) => ({ ...s, [updated.id]: updated }));
    refetch();
  };

  const requests = (data?.requests || [])
    .map((r) => answered[r.id] || r)
    .filter((r) => r.id !== requestId);
  const opened = requestId && single.data ? (answered[requestId] || single.data) : null;
  const totalPages = Math.max(1, Math.ceil((data?.total || 0) / PAGE_SIZE));

  const setQuery = (changes) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(changes)) {
      if (v) next.set(k, v); else next.delete(k);
    }
    setParams(next);
  };

  return (
    <>
      <div className="xp-toolbar">
        <Tabs
          items={[
            { value: '', label: 'To answer', count: data && !all ? data.waiting : null },
            { value: 'all', label: 'All requests' },
          ]}
          value={all ? 'all' : ''}
          onChange={(value) => setQuery({ filter: value, page: '' })}
        />
        <div className="xp-toolbar-right">
          <button className="btn btn-ghost btn-sm" onClick={refetch} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      <ErrorBanner>{error || single.error}</ErrorBanner>

      {opened && (
        <div className="rv-list">
          <RequestCard request={opened} onAnswered={onAnswered} highlight />
          <Link className="link-btn" to="/requests">All requests</Link>
        </div>
      )}

      {!data && !error && <Loader />}

      {data && requests.length === 0 && !opened && (
        <EmptyState icon={InboxIcon} title={all ? 'No requests yet' : 'Nothing to answer'} card>
          {all
            ? 'When a traveller asks for one of your packages, it shows here and you get a notification.'
            : 'You have answered every request. New ones show here and you get a notification.'}
        </EmptyState>
      )}

      <div className="rv-list">
        {requests.map((r) => <RequestCard key={r.id} request={r} onAnswered={onAnswered} />)}
      </div>

      <Pagination
        page={page} totalPages={totalPages}
        onPage={(p) => setQuery({ page: p > 1 ? String(p) : '' })}
      />
    </>
  );
}
