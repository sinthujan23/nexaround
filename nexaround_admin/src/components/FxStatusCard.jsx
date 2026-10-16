import { useEffect, useState } from 'react';
import { apiGet, apiPost } from '../api';
import { formatWhen, timeAgo } from '../audit';

const STATUS = {
  ok: ['badge-green', 'Up to date'],
  stale: ['badge-yellow', 'Stale: no good update for 48 hours'],
  error: ['badge-red', 'Last update failed'],
};

const SOURCE_LABELS = {
  'exchangerate-api': 'ExchangeRate-API (your key)',
  'open-er-api': 'ExchangeRate-API open endpoint (no key)',
};

function Row({ label, children }) {
  return (
    <div className="fx-row">
      <div className="fx-row-label">{label}</div>
      <div className="fx-row-value">{children}</div>
    </div>
  );
}

/**
 * The currency-rate monitor: when the rates were last published and fetched,
 * whether the last try worked, how much of the month's allowance is left.
 * `version` changes after a settings save, so a new key is checked at once.
 */
export default function FxStatusCard({ version }) {
  const [status, setStatus] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    apiGet('/admin/fx/status')
      .then((res) => { if (active) { setStatus(res); setError(''); } })
      .catch((err) => { if (active) setError(err.message || 'Could not load the currency status.'); });
    return () => { active = false; };
  }, [version]);

  const refresh = async () => {
    setBusy(true);
    setError('');
    try {
      setStatus(await apiPost('/admin/fx/refresh', {}));
    } catch (err) {
      setError(err.message || 'Refresh failed.');
    } finally {
      setBusy(false);
    }
  };

  if (!status && !error) return <div className="loader" />;

  const [badge, label] = STATUS[status?.status] || STATUS.stale;
  const q = status?.quota;

  return (
    <div className="fx-card">
      {error && <div className="login-error" style={{ marginBottom: 12 }}>{error}</div>}
      {status && (
        <>
          <div className="fx-head">
            <span className={`badge ${badge}`}>{label}</span>
            <button type="button" className="btn btn-ghost btn-sm" disabled={busy} onClick={refresh}>
              {busy ? 'Refreshing…' : 'Refresh now'}
            </button>
          </div>
          <Row label="Source">{SOURCE_LABELS[status.source] || status.source || '—'}</Row>
          <Row label="Provider published">
            {formatWhen(status.provider_updated_at)}
            {status.provider_updated_at && <span className="muted"> · {timeAgo(status.provider_updated_at)}</span>}
          </Row>
          <Row label="Next publish">{formatWhen(status.next_update_at)}</Row>
          <Row label="We last fetched">{formatWhen(status.fetched_at)}</Row>
          <Row label="Last attempt">{formatWhen(status.last_attempt_at)}</Row>
          {status.last_error && <Row label="Last error"><span className="fx-error">{status.last_error}</span></Row>}
          <Row label="Monthly requests">
            {q
              ? `${q.requests_used ?? '—'} used of ${q.plan_quota ?? '—'} · ${q.requests_remaining ?? '—'} left · resets on day ${q.refresh_day_of_month ?? '—'} of the month`
              : (status.has_key ? 'Could not read the quota' : 'No key: the open endpoint has no quota to show')}
          </Row>
          <Row label="Currencies">{status.currency_count}</Row>
          {Object.keys(status.samples || {}).length > 0 && (
            <div className="fx-samples">
              {Object.entries(status.samples).map(([code, rate]) => (
                <div key={code} className="fx-sample">
                  <span>1 USD</span>
                  <strong>{Number(rate).toLocaleString(undefined, { maximumFractionDigits: 4 })} {code}</strong>
                </div>
              ))}
            </div>
          )}
          <p className="fx-note">
            Rates are published once a day. The server fetches them shortly after each
            publish (about 30 requests a month) and the app converts every experience price
            with them. Refresh now uses one request.
          </p>
        </>
      )}
    </div>
  );
}
