import { useCallback, useEffect, useState } from 'react';
import { apiGet, apiPost } from '../api';
import { useAuth } from '../auth';

function formatDate(value) {
  if (!value) return '';
  return new Date(value).toLocaleDateString(undefined, {
    day: 'numeric', month: 'short', year: 'numeric',
  });
}

/**
 * The server's small document format: "## " heading, "- " bullet, a blank line
 * between paragraphs. The same rules as the app's legal_body.dart, so a
 * document reads the same everywhere it is shown.
 */
export function LegalBody({ body }) {
  const blocks = [];
  let paragraph = [];
  const flush = () => {
    if (paragraph.length) blocks.push({ type: 'p', text: paragraph.join(' ') });
    paragraph = [];
  };
  for (const raw of (body || '').split('\n')) {
    const line = raw.trim();
    if (!line) {
      flush();
    } else if (line.startsWith('## ')) {
      flush();
      blocks.push({ type: 'h', text: line.slice(3).trim() });
    } else if (line.startsWith('- ')) {
      flush();
      const last = blocks[blocks.length - 1];
      if (last?.type === 'ul') last.items.push(line.slice(2).trim());
      else blocks.push({ type: 'ul', items: [line.slice(2).trim()] });
    } else {
      paragraph.push(line);
    }
  }
  flush();

  return (
    <div className="legal-body">
      {blocks.map((block, i) => {
        if (block.type === 'h') return <h3 key={i}>{block.text}</h3>;
        if (block.type === 'ul') {
          return <ul key={i}>{block.items.map((item, j) => <li key={j}>{item}</li>)}</ul>;
        }
        return <p key={i}>{block.text}</p>;
      })}
    </div>
  );
}

/**
 * Stands in front of the whole portal until the vendor has accepted the
 * current Provider Agreement, and again whenever a new version is published.
 *
 * A failure to load fails open: the gate is there to collect acceptance, not
 * to guard data (the server already scopes every request), and a network blip
 * must not lock a vendor out of their enquiries. It asks again on the next
 * sign-in or reload.
 */
export function AgreementGate({ children }) {
  const { token, me, logout } = useAuth();
  const [status, setStatus] = useState(null);
  const [failed, setFailed] = useState(false);
  // Set when the agreement changed while the vendor was reading it.
  const [notice, setNotice] = useState('');

  const load = useCallback(() => {
    setFailed(false);
    return apiGet('/partner/agreement').then(setStatus).catch(() => setFailed(true));
  }, []);

  useEffect(() => {
    if (token) load();
  }, [token, load]);

  if (failed) return children;
  if (!status) return <div className="agreement-loading">Loading…</div>;
  if (!status.required) return children;

  return (
    <AgreementScreen
      // A new version starts with the box unticked.
      key={status.document.version}
      status={status}
      vendorName={me?.vendor_name}
      notice={notice}
      onAccepted={(next) => { setNotice(''); setStatus(next); }}
      onConflict={(message) => { setNotice(message); load(); }}
      onSignOut={logout}
    />
  );
}

function AgreementScreen({ status, vendorName, notice, onAccepted, onConflict, onSignOut }) {
  const [authorised, setAuthorised] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const doc = status.document;
  const business = vendorName || 'your business';
  const isUpdate = status.accepted_version != null;

  const accept = async () => {
    if (!authorised) {
      setError('Tick the box to confirm before continuing.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      onAccepted(await apiPost('/partner/agreement/accept', {
        version: doc.version, authorised: true,
      }));
    } catch (e) {
      // A 409 means a new version was published; anything else, show it.
      const message = e.message || 'Could not save your acceptance. Please try again.';
      if (/updated/i.test(message)) onConflict(message);
      else setError(message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="agreement-page">
      <div className="agreement-card">
        <div className="agreement-brand">
          <span className="logo-tile">
            <img src="/logo_2.png" alt="" onError={(e) => { e.currentTarget.style.display = 'none'; }} />
          </span>
          <span>nexARound <small>Partner Portal</small></span>
        </div>

        <h1 className="agreement-title">{doc.title}</h1>
        <p className="agreement-intro">
          {isUpdate
            ? `We have updated the ${doc.title}. Please review version ${doc.version} and accept it to continue.`
            : `Before you continue, please read and accept the ${doc.title} for ${business}.`}
        </p>

        {notice && <div className="login-error">{notice}</div>}
        <div className={`agreement-deadline ${status.listed ? '' : 'urgent'}`}>
          {status.listed
            ? `Please accept by ${formatDate(status.grace_ends_at)}. After that, your experiences are hidden from the nexARound app until you do.`
            : 'Your experiences are hidden from the nexARound app until you accept.'}
        </div>

        {doc.highlights?.length > 0 && (
          <ul className="agreement-highlights">
            {doc.highlights.map((line) => <li key={line}>{line}</li>)}
          </ul>
        )}

        <div className="agreement-doc">
          <div className="agreement-meta">
            Version {doc.version} · Published {formatDate(doc.published_at)}
          </div>
          <LegalBody body={doc.body} />
        </div>

        <label className="agreement-check">
          <input
            type="checkbox"
            checked={authorised}
            onChange={(e) => { setAuthorised(e.target.checked); setError(''); }}
          />
          <span>
            I have read and accept the {doc.title} on behalf of <strong>{business}</strong>,
            and I confirm that I am authorised to do so.
          </span>
        </label>

        {error && <div className="login-error">{error}</div>}

        <div className="agreement-actions">
          <button type="button" className="btn btn-ghost" onClick={onSignOut}>Sign out</button>
          <button type="button" className="btn btn-primary" disabled={busy} onClick={accept}>
            {busy ? 'Saving…' : 'Accept and continue'}
          </button>
        </div>
      </div>
    </div>
  );
}

/** The agreement as accepted, to re-read later from the sidebar. */
export function AgreementPage() {
  const [status, setStatus] = useState(null);

  useEffect(() => {
    apiGet('/partner/agreement').then(setStatus).catch(() => setStatus(false));
  }, []);

  if (status === null) return <div className="card">Loading…</div>;
  if (!status) return <div className="card">Couldn't load the agreement. Please reload the page.</div>;

  const doc = status.document;
  return (
    <div className="card agreement-view">
      <div className="agreement-meta">
        {doc.title} · Version {doc.version} ·{' '}
        {status.accepted_version >= doc.version
          ? `Accepted on ${formatDate(status.accepted_at)}`
          : 'Not accepted yet'}
      </div>
      <LegalBody body={doc.body} />
    </div>
  );
}
