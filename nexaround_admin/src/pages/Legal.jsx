import { useState } from 'react';
import { useApi, apiPost, apiPut } from '../api';
import { useToast } from '../hooks';
import { Badge, Card, Drawer, EmptyState, Modal, PageError, PageLoading, Toast } from '../components/Kit';
import { ClipboardCheckIcon, EditIcon } from '../components/Icons';

const AUDIENCE = {
  experience_customer: { label: 'Travellers', where: 'the app, before every experience request' },
  experience_provider: { label: 'Vendors', where: 'the partner portal, before anything else' },
};

const formatDate = (value) => (value
  ? new Date(value).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
  : '');

/**
 * The server's small document format, as the app and the portal render it:
 * "## " heading, "- " bullet, a blank line between paragraphs.
 */
function LegalPreview({ body }) {
  const blocks = [];
  let paragraph = [];
  const flush = () => {
    if (paragraph.length) blocks.push({ type: 'p', text: paragraph.join(' ') });
    paragraph = [];
  };
  for (const raw of (body || '').split('\n')) {
    const line = raw.trim();
    if (!line) flush();
    else if (line.startsWith('## ')) { flush(); blocks.push({ type: 'h', text: line.slice(3).trim() }); }
    else if (line.startsWith('- ')) {
      flush();
      const last = blocks[blocks.length - 1];
      if (last?.type === 'ul') last.items.push(line.slice(2).trim());
      else blocks.push({ type: 'ul', items: [line.slice(2).trim()] });
    } else paragraph.push(line);
  }
  flush();
  return (
    <div className="legal-preview">
      {blocks.map((b, i) => {
        if (b.type === 'h') return <h4 key={i}>{b.text}</h4>;
        if (b.type === 'ul') return <ul key={i}>{b.items.map((t, j) => <li key={j}>{t}</li>)}</ul>;
        return <p key={i}>{b.text}</p>;
      })}
    </div>
  );
}

/**
 * Admin > Legal & Terms. The two documents travellers and vendors accept, and
 * who has accepted the vendor one. Publishing a new version makes everyone
 * accept again; a correction does not, so it is for typos only.
 */
export default function Legal() {
  const docs = useApi('/admin/legal');
  const vendors = useApi('/admin/legal/vendors');
  const [editing, setEditing] = useState(null);
  const [offlineFor, setOfflineFor] = useState(null);
  const [toast, notify] = useToast();

  if (docs.loading && !docs.data) return <PageLoading />;
  if (docs.error && !docs.data) return <PageError error={docs.error} onRetry={docs.refetch} />;

  return (
    <div>
      <Toast toast={toast} />

      <p style={{ margin: '0 0 18px', color: 'var(--text-secondary)', fontSize: '13px', lineHeight: 1.6, maxWidth: 820 }}>
        What travellers and vendors agree to before using Experiences. Every acceptance is recorded with
        the version, time and device, and each request stores the version its traveller accepted.
        Have any change of meaning reviewed by your lawyer before publishing it.
      </p>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(340px, 1fr))', gap: 20, marginBottom: 20 }}>
        {(docs.data || []).map((doc) => (
          <DocumentCard key={doc.kind} doc={doc} onEdit={() => setEditing(doc)} />
        ))}
      </div>

      <VendorAcceptance state={vendors} onRecord={setOfflineFor} />

      {editing && (
        <DocumentEditor
          doc={editing}
          onClose={() => setEditing(null)}
          onSaved={(message) => {
            setEditing(null);
            notify(message);
            docs.refetch();
            vendors.refetch();
          }}
        />
      )}
      {offlineFor && (
        <OfflineAcceptance
          vendor={offlineFor}
          version={vendors.data?.current_version}
          onClose={() => setOfflineFor(null)}
          onSaved={() => {
            setOfflineFor(null);
            notify('Acceptance recorded');
            vendors.refetch();
          }}
        />
      )}
    </div>
  );
}

function DocumentCard({ doc, onEdit }) {
  const audience = AUDIENCE[doc.kind] || { label: doc.kind, where: '' };
  return (
    <Card
      title={(
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <ClipboardCheckIcon size={18} style={{ color: 'var(--accent)' }} />
          <span>{doc.title}</span>
        </div>
      )}
      action={(
        <button type="button" className="btn btn-ghost btn-sm" onClick={onEdit}>
          <EditIcon size={14} /> Edit
        </button>
      )}
    >
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 12 }}>
        <Badge tone="green">Version {doc.version}</Badge>
        <Badge tone="ghost">{audience.label}</Badge>
      </div>
      <div style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Shown in {audience.where}.<br />
        Published {formatDate(doc.published_at)}
        {doc.updated_at !== doc.published_at && ` · corrected ${formatDate(doc.updated_at)}`}
        {doc.updated_by && ` · by ${doc.updated_by}`}
      </div>
      {doc.highlights?.length > 0 && (
        <ul style={{ margin: '14px 0 0', paddingLeft: 18, fontSize: 13, lineHeight: 1.6 }}>
          {doc.highlights.map((line) => <li key={line}>{line}</li>)}
        </ul>
      )}
      {doc.versions?.length > 1 && (
        <div style={{ marginTop: 14, fontSize: 12, color: 'var(--text-muted)' }}>
          History: {doc.versions.map((v) => `v${v.version} (${formatDate(v.published_at)})`).join(' · ')}
        </div>
      )}
    </Card>
  );
}

function DocumentEditor({ doc, onClose, onSaved }) {
  const [title, setTitle] = useState(doc.title);
  const [highlights, setHighlights] = useState((doc.highlights || []).join('\n'));
  const [body, setBody] = useState(doc.body);
  const [preview, setPreview] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const audience = AUDIENCE[doc.kind]?.label.toLowerCase() || 'everyone';

  const save = async (newVersion) => {
    if (newVersion && !confirm(
      `Publish version ${doc.version + 1}? All ${audience} will be asked to accept it again.`
      + (doc.kind === 'experience_provider'
        ? ' Vendors who have not accepted it within 14 days are hidden from the app.'
        : ''),
    )) return;
    setBusy(true);
    setError('');
    try {
      await apiPut(`/admin/legal/${doc.kind}`, {
        title,
        body,
        highlights: highlights.split('\n'),
        new_version: newVersion,
      });
      onSaved(newVersion ? `Version ${doc.version + 1} published` : 'Correction saved');
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Drawer
      title={`Edit ${doc.title}`}
      subtitle={`Version ${doc.version}`}
      onClose={onClose}
      footer={(
        <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end', flexWrap: 'wrap', width: '100%' }}>
          <button type="button" className="btn btn-ghost" disabled={busy} onClick={() => save(false)}
            title="For typos only: people who accepted this version are not asked again">
            Save correction
          </button>
          <button type="button" className="btn btn-primary" disabled={busy} onClick={() => save(true)}>
            Publish as version {doc.version + 1}
          </button>
        </div>
      )}
    >
      {error && <div className="login-error" style={{ marginBottom: 16 }}>{error}</div>}
      <div className="form-group">
        <label className="form-label">Title</label>
        <input className="form-input" value={title} onChange={(e) => setTitle(e.target.value)} />
      </div>
      <div className="form-group">
        <label className="form-label">Highlights (one per line, up to 6)</label>
        <textarea
          className="form-input" rows={5} value={highlights}
          onChange={(e) => setHighlights(e.target.value)}
        />
        <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 6 }}>
          The short rules shown where people commit: the app&apos;s &quot;Good to know&quot; card and request
          sheet, and the top of the vendor agreement.
        </div>
      </div>
      <div className="form-group">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <label className="form-label" style={{ margin: 0 }}>Full text</label>
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => setPreview((p) => !p)}>
            {preview ? 'Edit' : 'Preview'}
          </button>
        </div>
        {preview ? <LegalPreview body={body} /> : (
          <textarea
            className="form-input" rows={22} value={body}
            onChange={(e) => setBody(e.target.value)}
            style={{ fontFamily: 'ui-monospace, Consolas, monospace', fontSize: 12.5, lineHeight: 1.55, marginTop: 8 }}
          />
        )}
        <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 6 }}>
          Start a heading with <code>## </code>, a bullet with <code>- </code>, and leave a blank
          line between paragraphs. Nothing else is formatted.
        </div>
      </div>
      <div className="login-error" style={{ background: 'rgba(255,179,0,0.1)', color: '#6b4e00', borderColor: 'rgba(255,179,0,0.4)' }}>
        <strong>Save correction</strong> fixes typos in version {doc.version} without asking anyone again.
        Anything that changes what people agree to must be <strong>published as a new version</strong>.
      </div>
    </Drawer>
  );
}

function VendorAcceptance({ state, onRecord }) {
  const { data, loading, error, refetch } = state;
  const rows = data?.vendors || [];
  const pending = rows.filter((v) => !v.is_current).length;

  return (
    <Card
      title={(
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span>Provider Agreement acceptance</span>
          {data && (
            <span style={{ fontSize: 12, fontWeight: 500, color: 'var(--text-secondary)' }}>
              ({rows.length - pending} of {rows.length} on version {data.current_version})
            </span>
          )}
        </div>
      )}
    >
      {error && !data && <PageError inline error={error} onRetry={refetch} />}
      {data && pending > 0 && (
        <div className="login-error" style={{ marginBottom: 16, background: 'rgba(255,179,0,0.1)', color: '#6b4e00', borderColor: 'rgba(255,179,0,0.4)' }}>
          {new Date(data.grace_ends_at) > new Date()
            ? `${pending} vendor${pending === 1 ? ' has' : 's have'} not accepted version ${data.current_version}. From ${formatDate(data.grace_ends_at)} their experiences are hidden from the app until they do.`
            : `${pending} vendor${pending === 1 ? ' has' : 's have'} not accepted version ${data.current_version}, so their experiences are hidden from the app.`}
          {' '}Vendors accept when they next sign in to the partner portal; for one who signed on paper, record it here.
        </div>
      )}
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Vendor</th>
              <th>Status</th>
              <th>Accepted</th>
              <th>By</th>
              <th>In the app</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
              <tr>
                <td colSpan="6">
                  {loading ? 'Loading…' : <EmptyState title="No vendors yet" />}
                </td>
              </tr>
            ) : rows.map((v) => (
              <tr key={v.vendor_id}>
                <td style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                  {v.vendor_name}
                  {!v.vendor_is_active && <Badge tone="ghost" style={{ marginLeft: 8 }}>Inactive</Badge>}
                </td>
                <td>
                  {v.is_current
                    ? <Badge tone="green">Accepted v{v.accepted_version}</Badge>
                    : v.accepted_version
                      ? <Badge tone="yellow">Outdated (v{v.accepted_version})</Badge>
                      : <Badge tone="red">Not accepted</Badge>}
                </td>
                <td style={{ color: 'var(--text-secondary)' }}>
                  {v.accepted_at ? formatDate(v.accepted_at) : '—'}
                  {v.method === 'offline' && <div style={{ fontSize: 12 }}>Offline{v.note ? `: ${v.note}` : ''}</div>}
                </td>
                <td style={{ color: 'var(--text-secondary)', fontSize: 13 }}>{v.accepted_by || '—'}</td>
                <td>{v.listed ? <Badge tone="green">Listed</Badge> : <Badge tone="red">Hidden</Badge>}</td>
                <td style={{ textAlign: 'right' }}>
                  {!v.is_current && (
                    <button type="button" className="btn btn-ghost btn-sm" onClick={() => onRecord(v)}>
                      Record offline acceptance
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function OfflineAcceptance({ vendor, version, onClose, onSaved }) {
  const [acceptedOn, setAcceptedOn] = useState(new Date().toISOString().slice(0, 10));
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      await apiPost(`/admin/legal/vendors/${vendor.vendor_id}/offline-acceptance`, {
        accepted_on: acceptedOn, note,
      });
      onSaved();
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={`Record acceptance · ${vendor.vendor_name}`} onClose={onClose} maxWidth="480px">
      <form onSubmit={submit}>
        <p style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.6, marginTop: 0 }}>
          For a vendor who accepted version {version} outside the portal, for example by signing the partner
          form. Only record this if you hold that evidence.
        </p>
        {error && <div className="login-error" style={{ marginBottom: 12 }}>{error}</div>}
        <div className="form-group">
          <label className="form-label">Date accepted</label>
          <input type="date" className="form-input" value={acceptedOn} onChange={(e) => setAcceptedOn(e.target.value)} required />
        </div>
        <div className="form-group">
          <label className="form-label">Evidence</label>
          <textarea
            className="form-input" rows={3} value={note} required minLength={3}
            placeholder="e.g. Signed partner form, filed in Drive › Vendors › Lagoon Tours"
            onChange={(e) => setNote(e.target.value)}
          />
        </div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
          <button type="button" className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={busy || note.trim().length < 3}>
            {busy ? 'Saving…' : 'Record acceptance'}
          </button>
        </div>
      </form>
    </Modal>
  );
}
