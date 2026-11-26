import { useCallback, useEffect, useRef, useState } from 'react';
import { apiDownload, apiGet, apiPost } from '../api';
import {
  AlertTriangleIcon, BotIcon, CrossIcon, DownloadIcon, FileIcon, ImageIcon, InboxIcon, MailIcon,
  MaximizeIcon, PaperclipIcon, PenIcon, RefreshIcon, ReplyAllIcon, ReplyIcon, SearchIcon, SendIcon,
  TrashIcon,
} from '../components/Icons';
import { Drawer, Toast } from '../components/Kit';
import { useToast } from '../hooks';
import { notifySupportMailChanged } from '../supportMail';

// support@nexaround.com, read live from Hostinger: what is read, sent or
// deleted here is the same in Hostinger webmail. Opening a mail marks it
// read. Replies and new mails go out from support@ and are kept in Sent.
// Layout: folders | mails grouped by day | the open mail with a quick reply.

const FOLDERS = [
  { key: 'inbox', label: 'Inbox', Icon: InboxIcon },
  { key: 'sent', label: 'Sent', Icon: SendIcon },
  { key: 'system', label: 'System', Icon: BotIcon },
  { key: 'junk', label: 'Junk', Icon: AlertTriangleIcon },
  { key: 'trash', label: 'Trash', Icon: TrashIcon },
];
// Folders of mails sent from support@: the list shows who each went to, and
// there is nothing to reply to. System holds the app's automatic mails.
const OUTGOING = ['sent', 'system'];
// Folders whose mails can be answered from here.
const REPLYABLE = ['inbox', 'junk'];
const FILTERS = [['all', 'All'], ['unread', 'Unread'], ['replied', 'Replied'], ['files', 'With files']];
const OUTGOING_FILTERS = ['all', 'files'];

const EMPTY = {
  inbox: 'Mails sent to support@nexaround.com show here.',
  sent: 'Mails you send from here, or from Hostinger webmail, show here.',
  system: 'Copies of the mails the app sends by itself show here, with codes and sign-in links hidden.',
  junk: 'Mails Hostinger thinks are spam land here.',
  trash: 'Deleted mails stay here until Hostinger empties the Trash.',
};

const TZ = 'Asia/Colombo';
const AVATAR_COLORS = ['#0e7c86', '#7c3aed', '#db2777', '#ea580c', '#2563eb', '#059669', '#ca8a04', '#475569', '#dc2626'];

// Days counted in Sri Lanka time, like every date on this page.
const dayKey = (date) => date.toLocaleDateString('en-CA', { timeZone: TZ });
const daysAgo = (value) => {
  const ms = Date.parse(dayKey(new Date())) - Date.parse(dayKey(new Date(value)));
  return Math.round(ms / 86400000);
};

const formatDateTime = (value) => (value
  ? new Date(value).toLocaleString('en-GB', {
    weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: TZ,
  })
  : '');
const formatClock = (value) => new Date(value).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: TZ });

// The time beside each mail in the list.
const rowTime = (value) => {
  if (!value) return '';
  const days = daysAgo(value);
  const date = new Date(value);
  if (days <= 0) return formatClock(value);
  if (days === 1) return 'Yesterday';
  if (days < 7) return date.toLocaleDateString('en-GB', { weekday: 'short', timeZone: TZ });
  const sameYear = dayKey(date).slice(0, 4) === dayKey(new Date()).slice(0, 4);
  return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', ...(sameYear ? {} : { year: 'numeric' }), timeZone: TZ });
};

// The day heading a mail sits under in the list.
const groupLabel = (value) => {
  if (!value) return 'No date';
  const days = daysAgo(value);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 7) return 'This week';
  return new Date(value).toLocaleDateString('en-GB', { month: 'long', year: 'numeric', timeZone: TZ });
};

// "Today, 10:42" above the full date in the open mail.
const shortWhen = (value) => {
  if (!value) return '';
  const days = daysAgo(value);
  if (days <= 0) return `Today, ${formatClock(value)}`;
  if (days === 1) return `Yesterday, ${formatClock(value)}`;
  return formatClock(value);
};

const formatSize = (bytes) => {
  if (bytes == null) return '';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
};

const fileType = (name) => {
  const m = /\.([a-z0-9]{1,5})$/i.exec(name || '');
  return m ? m[1].toUpperCase() : 'File';
};

const personName = (p) => (p ? p.name || p.email : '');
const firstName = (p) => (p?.name ? p.name.split(/\s+/)[0] : p?.email || '');
const personFull = (p) => (p ? (p.name ? `${p.name} <${p.email}>` : p.email) : '');
const people = (list) => (list || []).map(personFull).join(', ');

const splitAddresses = (value) => value.split(/[,;\s]+/).map((a) => a.trim()).filter(Boolean);
const looksLikeEmail = (value) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);

const reSubject = (subject) => (/^re:/i.test(subject || '') ? subject : `Re: ${subject || ''}`.trim());

function Avatar({ person, size = 36 }) {
  const label = person?.name || (person?.email || '?').split('@')[0];
  const words = label.replace(/[^\p{L}\p{N}\s]/gu, ' ').trim().split(/\s+/).filter(Boolean);
  const initials = ((words[0]?.[0] || '?') + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase();
  const key = person?.email || label;
  let hash = 0;
  for (let i = 0; i < key.length; i += 1) hash = Math.imul(hash ^ key.charCodeAt(i), 2654435761) >>> 0;
  return (
    <span
      className="mbx-avatar"
      style={{ width: size, height: size, fontSize: Math.round(size * 0.38), background: AVATAR_COLORS[hash % AVATAR_COLORS.length] }}
      aria-hidden="true"
    >
      {initials}
    </span>
  );
}

// Plain-text mails: keep the line breaks, make web addresses clickable.
function PlainText({ text }) {
  const parts = (text || '').split(/(https?:\/\/[^\s<>"]+)/g);
  return (
    <div className="mail-plain">
      {parts.map((part, i) => (/^https?:\/\//.test(part)
        ? <a key={i} href={part} target="_blank" rel="noreferrer noopener">{part}</a>
        : part))}
    </div>
  );
}

/**
 * A mail's HTML in a sandboxed frame: no scripts, no forms, and (until
 * "Show images") nothing loaded from outside, which also stops tracking
 * pixels. Links open in a new tab. The frame grows to fit the mail.
 */
function MailFrame({ html, showImages }) {
  const ref = useRef(null);
  const images = showImages ? 'https: http: data:' : 'data:';
  const doc = `<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src ${images}; style-src 'unsafe-inline'; font-src data:">
<base target="_blank">
<style>body{margin:0;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;font-size:14.5px;line-height:1.6;color:#2b3140;word-wrap:break-word}img{max-width:100%;height:auto}table{max-width:100%}</style>
</head><body>${html}</body></html>`;

  const fit = useCallback(() => {
    const frame = ref.current;
    const body = frame?.contentDocument?.documentElement;
    if (body) frame.style.height = `${body.scrollHeight + 8}px`;
  }, []);

  const onLoad = () => {
    fit();
    const d = ref.current?.contentDocument;
    if (d) Array.from(d.images).forEach((img) => img.addEventListener('load', fit));
  };

  return (
    <iframe
      ref={ref}
      title="Email"
      className="mail-frame"
      sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox"
      srcDoc={doc}
      onLoad={onLoad}
    />
  );
}

function Compose({ draft, sending, onChange, onClose, onSend }) {
  const set = (key) => (e) => onChange({ ...draft, [key]: e.target.value });
  return (
    <Drawer
      wide
      title={draft.reply ? 'Reply' : 'New email'}
      subtitle="From support@nexaround.com"
      onClose={onClose}
      onSubmit={(e) => { e.preventDefault(); onSend(); }}
      footer={(
        <>
          <button type="button" className="btn btn-ghost" onClick={onClose}>Cancel</button>
          <button type="submit" className="btn btn-primary" disabled={sending}>
            <SendIcon size={15} /> {sending ? 'Sending…' : 'Send'}
          </button>
        </>
      )}
    >
      <div className="form-group">
        <label className="form-label" htmlFor="mail-to">To</label>
        <input id="mail-to" className="form-input" value={draft.to} onChange={set('to')} placeholder="name@example.com" autoFocus={!draft.reply} />
      </div>
      <div className="form-group">
        <label className="form-label" htmlFor="mail-cc">Cc</label>
        <input id="mail-cc" className="form-input" value={draft.cc} onChange={set('cc')} placeholder="Optional. Separate addresses with commas" />
      </div>
      <div className="form-group">
        <label className="form-label" htmlFor="mail-subject">Subject</label>
        <input id="mail-subject" className="form-input" value={draft.subject} onChange={set('subject')} maxLength={300} />
      </div>
      <div className="form-group">
        <label className="form-label" htmlFor="mail-body">Message</label>
        <textarea id="mail-body" className="form-textarea" rows={14} value={draft.body} onChange={set('body')} autoFocus={!!draft.reply} />
        {draft.reply && (
          <div className="mail-note">The earlier message is quoted below yours when it is sent.</div>
        )}
      </div>
    </Drawer>
  );
}

function ListSkeleton() {
  return (
    <div className="mbx-skeleton" aria-label="Loading">
      {[0, 1, 2, 3, 4, 5].map((i) => (
        <div key={i} className="mbx-skel-row">
          <span className="mbx-skel-dot" />
          <div><span style={{ width: '45%' }} /><span style={{ width: '80%' }} /><span style={{ width: '65%' }} /></div>
        </div>
      ))}
    </div>
  );
}

export default function SupportInbox() {
  const [folder, setFolder] = useState('inbox');
  const [show, setShow] = useState('all');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [list, setList] = useState(null); // { messages, total, has_more, page, unread }
  const [listError, setListError] = useState(null);
  const [counts, setCounts] = useState(null); // { inbox: { total, unread }, ... }
  const [loadingMore, setLoadingMore] = useState(false);
  const [selectedUid, setSelectedUid] = useState(null);
  const [mail, setMail] = useState(null);
  const [mailError, setMailError] = useState(null);
  const [showImages, setShowImages] = useState(false);
  const [draft, setDraft] = useState(null);
  const [quick, setQuick] = useState('');
  const [quickFocus, setQuickFocus] = useState(false);
  const [sending, setSending] = useState(false);
  const [busy, setBusy] = useState(false);
  const [toast, notify] = useToast(3500);
  const listRun = useRef(0);
  const readRun = useRef(0);

  const listUrl = useCallback((page) => {
    const params = new URLSearchParams({ page: String(page) });
    if (query) params.set('q', query);
    if (show !== 'all') params.set('show', show);
    return `/admin/support-mail/folders/${folder}?${params}`;
  }, [folder, query, show]);

  // Search waits for a pause in typing.
  useEffect(() => {
    const t = setTimeout(() => {
      const next = search.trim();
      setQuery((prev) => {
        if (prev !== next) setList(null);
        return next;
      });
    }, 450);
    return () => clearTimeout(t);
  }, [search]);

  // Page 1 again whenever the folder, filter or search changes, or Refresh is pressed.
  const [reloads, setReloads] = useState(0);
  useEffect(() => {
    const run = ++listRun.current;
    apiGet(listUrl(1))
      .then((res) => {
        if (run !== listRun.current) return;
        setListError(null);
        setList(res);
      })
      .catch((err) => {
        if (run === listRun.current) setListError(err.message || 'Could not load the mailbox.');
      });
  }, [listUrl, reloads]);

  // Folder counts: on load, on Refresh, and after a move or a send.
  const [countTicks, setCountTicks] = useState(0);
  useEffect(() => {
    apiGet('/admin/support-mail/counts').then(setCounts).catch(() => {});
  }, [countTicks]);
  const recount = () => setCountTicks((n) => n + 1);

  const loadMore = async () => {
    const run = ++listRun.current;
    setLoadingMore(true);
    try {
      const res = await apiGet(listUrl((list?.page || 1) + 1));
      if (run === listRun.current) {
        setList((prev) => (prev ? { ...res, messages: [...prev.messages, ...res.messages] } : res));
      }
    } catch (err) {
      notify(err.message || 'Could not load older mails.', 'error');
    } finally {
      setLoadingMore(false);
    }
  };

  const closeMail = () => { readRun.current += 1; setSelectedUid(null); setMail(null); setMailError(null); };

  const open = async (uid) => {
    const run = ++readRun.current;
    const wasUnread = list?.messages.find((m) => m.uid === uid)?.unread;
    setSelectedUid(uid);
    setMail(null);
    setMailError(null);
    setShowImages(false);
    setQuick('');
    try {
      const res = await apiGet(`/admin/support-mail/folders/${folder}/${uid}`);
      if (run !== readRun.current) return;
      setMail(res);
      // Opening marks it read: follow in the list, the folder count and the badge.
      if (wasUnread) {
        setList((prev) => prev && {
          ...prev,
          messages: prev.messages.map((m) => (m.uid === uid ? { ...m, unread: false } : m)),
        });
        setCounts((prev) => (prev?.[folder]
          ? { ...prev, [folder]: { ...prev[folder], unread: Math.max(0, prev[folder].unread - 1) } }
          : prev));
        notifySupportMailChanged();
      }
    } catch (err) {
      if (run === readRun.current) setMailError(err.message || 'Could not open this mail.');
    }
  };

  const switchFolder = (key) => {
    if (key === folder) return;
    setFolder(key);
    if (OUTGOING.includes(key) && !OUTGOING_FILTERS.includes(show)) setShow('all');
    setList(null);
    closeMail();
  };

  const switchFilter = (key) => {
    if (key === show) return;
    setShow(key);
    setList(null);
  };

  const refresh = () => { setList(null); setReloads((n) => n + 1); recount(); notifySupportMailChanged(); };

  const replyDraft = (all, body = '') => ({
    to: (mail.reply_to || []).map((p) => p.email).join(', '),
    cc: all ? (mail.reply_all_cc || []).map((p) => p.email).join(', ') : '',
    subject: reSubject(mail.subject),
    body,
    reply: { folder, uid: mail.uid },
  });

  const deliver = async (d) => {
    const to = splitAddresses(d.to);
    const cc = splitAddresses(d.cc);
    const bad = [...to, ...cc].filter((a) => !looksLikeEmail(a));
    if (!to.length) { notify('Add who it goes to.', 'error'); return false; }
    if (bad.length) { notify(`Check ${bad.join(', ')}: it doesn't look like an email address.`, 'error'); return false; }
    if (!d.subject.trim()) { notify('Add a subject.', 'error'); return false; }
    if (!d.body.trim()) { notify('Write a message first.', 'error'); return false; }
    setSending(true);
    try {
      const res = await apiPost('/admin/support-mail/send', {
        to, cc, subject: d.subject.trim(), body: d.body, reply: d.reply || null,
      });
      notify(res.saved_to_sent ? 'Sent' : 'Sent, but the copy could not be saved in Sent.');
      if (d.reply && mail && d.reply.uid === mail.uid) {
        setMail((prev) => prev && { ...prev, answered: true });
        setList((prev) => prev && {
          ...prev,
          messages: prev.messages.map((m) => (m.uid === d.reply.uid ? { ...m, answered: true } : m)),
        });
      }
      if (folder === 'sent') setReloads((n) => n + 1);
      recount();
      return true;
    } catch (err) {
      notify(err.message || 'The mail could not be sent.', 'error');
      return false;
    } finally {
      setSending(false);
    }
  };

  const sendDraft = async () => {
    if (await deliver(draft)) {
      if (draft.reply) setQuick('');
      setDraft(null);
    }
  };

  const sendQuick = async () => {
    if (await deliver(replyDraft(false, quick))) setQuick('');
  };

  const moveTo = async (to) => {
    const question = to === 'trash'
      ? 'Delete this mail? It moves to Trash (you can still find it in Hostinger webmail).'
      : 'Move this mail to the Inbox?';
    if (!window.confirm(question)) return;
    setBusy(true);
    try {
      await apiPost(`/admin/support-mail/folders/${folder}/${mail.uid}/move`, { to });
      setList((prev) => prev && {
        ...prev,
        total: Math.max(0, prev.total - 1),
        messages: prev.messages.filter((m) => m.uid !== mail.uid),
      });
      closeMail();
      recount();
      notifySupportMailChanged();
      notify(to === 'trash' ? 'Moved to Trash' : 'Moved to the Inbox');
    } catch (err) {
      notify(err.message || 'Could not move the mail.', 'error');
    } finally {
      setBusy(false);
    }
  };

  const download = async (a) => {
    try {
      const blob = await apiDownload(`/admin/support-mail/folders/${folder}/${mail.uid}/attachments/${a.index}`);
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = a.filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 10000);
    } catch (err) {
      notify(err.message || 'Could not download the file.', 'error');
    }
  };

  const messages = list?.messages || [];
  const outgoing = OUTGOING.includes(folder);
  const canReply = REPLYABLE.includes(folder);
  const filters = outgoing ? FILTERS.filter(([key]) => OUTGOING_FILTERS.includes(key)) : FILTERS;
  const folderLabel = FOLDERS.find((f) => f.key === folder)?.label;

  // Rows with a day heading above the first mail of each day group.
  const rows = messages.map((m, i) => {
    const group = groupLabel(m.date);
    const heading = i === 0 || groupLabel(messages[i - 1].date) !== group ? group : null;
    const person = outgoing ? (m.to || [])[0] : m.from;
    const who = outgoing
      ? `To: ${(m.to || []).map(personName).join(', ') || '—'}`
      : personName(m.from) || '(no sender)';
    return (
      <div key={m.uid}>
        {heading && <div className="mbx-group">{heading}</div>}
        <button
          type="button"
          className={`mbx-row ${selectedUid === m.uid ? 'active' : ''} ${m.unread ? 'unread' : ''}`}
          onClick={() => open(m.uid)}
        >
          <Avatar person={person} />
          <div className="mbx-row-main">
            <div className="mbx-row-top">
              <span className="mbx-row-who">{who}</span>
              <span className="mbx-row-time" title={formatDateTime(m.date)}>{rowTime(m.date)}</span>
            </div>
            <div className="mbx-row-subject">{m.subject || '(no subject)'}</div>
            <div className="mbx-row-snippet">{m.snippet || ' '}</div>
            {(m.answered || m.has_attachments) && (
              <div className="mbx-row-tags">
                {m.answered && <span className="mbx-chip replied"><ReplyIcon size={11} /> Replied</span>}
                {m.has_attachments && <span className="mbx-chip"><PaperclipIcon size={11} /> Attachment</span>}
              </div>
            )}
          </div>
          {m.unread && <span className="mbx-unread-dot" title="Unread" />}
        </button>
      </div>
    );
  });

  const quickRows = quickFocus || quick ? Math.min(8, Math.max(3, quick.split('\n').length + 1)) : 1;

  return (
    <div>
      <Toast toast={toast} />

      <div className={`mbx ${selectedUid ? 'has-selection' : ''}`}>
        {/* Folders */}
        <nav className="mbx-folders" aria-label="Folders">
          <button
            type="button"
            className="btn btn-primary mbx-compose"
            onClick={() => setDraft({ to: '', cc: '', subject: '', body: '', reply: null })}
          >
            <PenIcon size={16} /> New email
          </button>
          <div className="mbx-folder-list">
            {FOLDERS.map(({ key, label, Icon }) => {
              const c = counts?.[key];
              let count = null;
              if (key === 'inbox') count = c?.unread ? <em className="pill">{c.unread.toLocaleString()}</em> : null;
              else if (c?.total) count = <em>{c.total.toLocaleString()}</em>;
              return (
                <button
                  type="button"
                  key={key}
                  className={`mbx-folder ${folder === key ? 'active' : ''}`}
                  onClick={() => switchFolder(key)}
                >
                  <Icon size={17} />
                  <span>{label}</span>
                  {count}
                </button>
              );
            })}
          </div>
          <div className="mbx-folder-note">
            {folder === 'system'
              ? <><b>System</b> keeps copies of the emails the app sends by itself, with codes and sign-in links hidden.</>
              : <><b>Live from Hostinger.</b> What you read, send or delete here is the same in webmail.</>}
          </div>
        </nav>

        {/* Mails */}
        <section className="mbx-list" aria-label={`${folderLabel} mails`}>
          <div className="mbx-list-head">
            <div className="mbx-search">
              <SearchIcon size={16} />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search sender, subject or text"
                aria-label="Search mails"
              />
              {search && (
                <button type="button" className="mbx-search-clear" onClick={() => setSearch('')} title="Clear search">
                  <CrossIcon size={14} />
                </button>
              )}
            </div>
            <div className="mbx-filters">
              {filters.map(([key, label]) => (
                <button
                  type="button"
                  key={key}
                  className={`mbx-filter ${show === key ? 'active' : ''}`}
                  onClick={() => switchFilter(key)}
                >
                  {label}
                </button>
              ))}
              <button type="button" className="mbx-icon-btn mbx-refresh" onClick={refresh} title="Check for new mail">
                <RefreshIcon size={15} />
              </button>
            </div>
            <div className="mbx-list-count">
              {list
                ? `${list.total.toLocaleString()} ${query || show !== 'all' ? 'found' : (list.total === 1 ? 'mail' : 'mails')}`
                : 'Loading…'}
            </div>
          </div>

          <div className="mbx-list-body">
            {listError && <div className="login-error" style={{ margin: 12 }}>{listError}</div>}
            {!list && !listError && <ListSkeleton />}
            {list && messages.length === 0 && (
              <div className="xp-empty">
                <InboxIcon size={32} />
                <strong>{query || show !== 'all' ? 'Nothing matches' : `${folderLabel} is empty`}</strong>
                {query || show !== 'all' ? 'Try other words or another filter.' : EMPTY[folder]}
              </div>
            )}
            {rows}
            {list?.has_more && (
              <div className="mail-more">
                <button className="btn btn-ghost btn-sm" onClick={loadMore} disabled={loadingMore}>
                  {loadingMore ? 'Loading…' : 'Load older mails'}
                </button>
              </div>
            )}
          </div>
        </section>

        {/* The open mail */}
        <section className="mbx-read" aria-label="Mail">
          {!selectedUid && (
            <div className="xp-empty">
              <MailIcon size={36} />
              <strong>Select a mail to read it</strong>
              Opening a mail marks it read, here and in Hostinger webmail.
            </div>
          )}

          {selectedUid && !mail && !mailError && <div className="loader" />}

          {selectedUid && mailError && (
            <div className="xp-empty">
              <button type="button" className="mbx-back" onClick={closeMail}>← All mails</button>
              <AlertTriangleIcon size={32} />
              <strong>Couldn't open this mail</strong>
              {mailError}
            </div>
          )}

          {mail && (
            <>
              <div className="mbx-read-bar">
                <button type="button" className="mbx-back" onClick={closeMail}>← All mails</button>
                {canReply && (
                  <>
                    <button className="btn btn-primary btn-sm" onClick={() => setDraft(replyDraft(false, quick))}>
                      <ReplyIcon size={15} /> Reply
                    </button>
                    {mail.reply_all_cc?.length > 0 && (
                      <button className="btn btn-ghost btn-sm" onClick={() => setDraft(replyDraft(true, quick))} title="Reply all">
                        <ReplyAllIcon size={15} /> <span className="mbx-hide-sm">Reply all</span>
                      </button>
                    )}
                  </>
                )}
                {(folder === 'junk' || folder === 'trash') && (
                  <button className="btn btn-ghost btn-sm" onClick={() => moveTo('inbox')} disabled={busy}>
                    <InboxIcon size={15} /> {folder === 'junk' ? 'Not spam' : 'Move to Inbox'}
                  </button>
                )}
                {mail.answered && <span className="mbx-chip replied"><ReplyIcon size={11} /> Replied</span>}
                <span className="mbx-spacer" />
                {folder !== 'trash' && (
                  <button
                    type="button"
                    className="mbx-icon-btn mbx-delete"
                    onClick={() => moveTo('trash')}
                    disabled={busy}
                    title="Delete (moves to Trash)"
                  >
                    <TrashIcon size={16} />
                  </button>
                )}
              </div>

              <div className="mbx-read-scroll">
                <h2 className="mbx-subject">{mail.subject || '(no subject)'}</h2>
                <div className="mbx-from">
                  <Avatar person={mail.from} size={44} />
                  <div className="mbx-from-main">
                    <div className="mbx-from-name">
                      <b>{personName(mail.from) || '(no sender)'}</b>
                      {mail.from?.name && <span>&lt;{mail.from.email}&gt;</span>}
                    </div>
                    <div className="mbx-from-line">to {people(mail.to) || '—'}</div>
                    {mail.cc?.length > 0 && <div className="mbx-from-line">cc {people(mail.cc)}</div>}
                    {mail.reply_to?.length > 0 && mail.reply_to[0].email !== mail.from?.email && (
                      <div className="mbx-from-line">replies go to {people(mail.reply_to)}</div>
                    )}
                  </div>
                  <div className="mbx-from-when" title={formatDateTime(mail.date)}>
                    <b>{shortWhen(mail.date)}</b>
                    <span>{mail.date ? new Date(mail.date).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric', timeZone: TZ }) : ''}</span>
                  </div>
                </div>

                <div className="mbx-content">
                  {mail.html && mail.has_remote_images && !showImages && (
                    <div className="mail-images-note">
                      <ImageIcon size={15} />
                      Pictures from outside are hidden, so the sender can't tell you opened it.
                      <button className="btn btn-ghost btn-sm" onClick={() => setShowImages(true)}>Show images</button>
                    </div>
                  )}
                  {mail.html
                    ? <MailFrame key={`${mail.uid}-${showImages}`} html={mail.html} showImages={showImages} />
                    : <PlainText text={mail.text} />}

                  {mail.attachments?.length > 0 && (
                    <div className="mbx-files">
                      {mail.attachments.map((a) => (
                        <button key={a.index} type="button" className="mbx-file" onClick={() => download(a)} title="Download">
                          <FileIcon size={18} className="mbx-file-icon" />
                          <span className="mbx-file-text">
                            <b>{a.filename}</b>
                            <span>{[formatSize(a.size), fileType(a.filename)].filter(Boolean).join(' · ')}</span>
                          </span>
                          <DownloadIcon size={16} className="mbx-file-dl" />
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              {canReply && (
                <form
                  className={`mbx-quick ${quickFocus || quick ? 'open' : ''}`}
                  onSubmit={(e) => { e.preventDefault(); sendQuick(); }}
                >
                  <textarea
                    rows={quickRows}
                    value={quick}
                    onChange={(e) => setQuick(e.target.value)}
                    onFocus={() => setQuickFocus(true)}
                    onBlur={() => setQuickFocus(false)}
                    placeholder={`Reply to ${firstName(mail.reply_to?.[0] || mail.from) || 'sender'}…`}
                    aria-label="Quick reply"
                  />
                  <div className="mbx-quick-actions">
                    <button
                      type="button"
                      className="mbx-icon-btn"
                      onClick={() => setDraft(replyDraft(false, quick))}
                      title="Open the full editor (Cc, subject)"
                    >
                      <MaximizeIcon size={15} />
                    </button>
                    <button type="submit" className="btn btn-primary btn-sm" disabled={sending || !quick.trim()}>
                      <SendIcon size={14} /> {sending ? 'Sending…' : 'Send'}
                    </button>
                  </div>
                </form>
              )}
            </>
          )}
        </section>
      </div>

      {draft && (
        <Compose
          draft={draft}
          sending={sending}
          onChange={setDraft}
          onClose={() => !sending && setDraft(null)}
          onSend={sendDraft}
        />
      )}
    </div>
  );
}
