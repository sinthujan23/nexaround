import { useCallback, useEffect, useState } from 'react';
import { apiGet, apiPost } from '../../api';
import { useConfirm } from '../../confirm';
import { useToast } from '../../toast';
import { MonitorIcon, SmartphoneIcon, LogOutIcon } from '../../components/Icons';
import { EmptyState, ErrorBanner, ListRow, Loader } from '../../components/Lists';
import { formatAge, formatDateTime } from '../../format';
import { deviceLabel } from './format';

/**
 * Where this login is signed in. The list is this login only: a colleague's
 * login on the same business has its own, and nobody here can sign another
 * person out.
 */
export default function Devices() {
  const notify = useToast();
  const confirm = useConfirm();
  const [sessions, setSessions] = useState(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(null);

  const load = useCallback(() => (
    apiGet('/partner/sessions')
      .then((r) => setSessions(r.items))
      .catch((err) => setError(err.message || 'Could not load your devices.'))
  ), []);

  useEffect(() => { load(); }, [load]);

  const signOut = async (s) => {
    const ok = await confirm({
      title: `Sign out ${deviceLabel(s.browser, s.os)}?`,
      message: 'That device will need to sign in again.',
      confirmLabel: 'Sign out', danger: true,
    });
    if (!ok) return;
    setBusy(s.id);
    try {
      await apiPost(`/partner/sessions/${s.id}/revoke`);
      notify('Device signed out.');
      await load();
    } catch (err) {
      notify(err.message || 'Could not sign that device out.', 'error');
    } finally {
      setBusy(null);
    }
  };

  const signOutOthers = async () => {
    const ok = await confirm({
      title: 'Sign out every other device?',
      message: 'Only the device you are using now stays signed in.',
      confirmLabel: 'Sign them out', danger: true,
    });
    if (!ok) return;
    setBusy('others');
    try {
      const r = await apiPost('/partner/sessions/revoke-others');
      notify(r.message);
      await load();
    } catch (err) {
      notify(err.message || 'Could not sign the other devices out.', 'error');
    } finally {
      setBusy(null);
    }
  };

  const active = (sessions || []).filter((s) => s.status === 'active');
  const past = (sessions || []).filter((s) => s.status !== 'active');
  const others = active.filter((s) => !s.is_current).length;

  const row = (s) => {
    const Icon = s.device_type === 'mobile' || s.device_type === 'tablet' ? SmartphoneIcon : MonitorIcon;
    const live = s.status === 'active';
    return (
      <ListRow
        key={s.id}
        variant="sec"
        lead={<span className={`sec-tile ${live ? '' : 'muted'}`}><Icon size={20} /></span>}
        title={(
          <>
            {deviceLabel(s.browser, s.os)}
            {s.is_current && <span className="badge badge-green">This device</span>}
            {s.status === 'revoked' && <span className="badge badge-ghost">Signed out</span>}
            {s.status === 'ended' && <span className="badge badge-ghost">Expired</span>}
          </>
        )}
        subs={(
          <>
            {s.last_ip || s.ip || 'Unknown IP'} · Signed in {formatDateTime(s.created_at)}
            {live && ` · ${s.is_current ? 'Active now' : `Last active ${formatAge(s.last_seen_at)} ago`}`}
          </>
        )}
        side={live && !s.is_current && (
          <button
            type="button" className="btn btn-ghost btn-sm" disabled={busy === s.id}
            style={{ color: 'var(--danger)' }} onClick={() => signOut(s)}
          >
            <LogOutIcon size={14} /> Sign out
          </button>
        )}
      />
    );
  };

  return (
    <section className="card sec-card">
      <div className="sec-head">
        <div>
          <h2 className="sec-title">Where you're signed in</h2>
          <p className="sec-sub">If you don't recognise a device, sign it out, then reset your password from the sign-in page.</p>
        </div>
        {others > 0 && (
          <button type="button" className="btn btn-ghost btn-sm" disabled={busy === 'others'} onClick={signOutOthers}>
            Sign out all other devices
          </button>
        )}
      </div>
      <div className="sec-body">
        <ErrorBanner>{error}</ErrorBanner>
        {sessions === null && !error && <Loader />}
        {sessions && active.length === 0 && (
          <EmptyState icon={MonitorIcon} title="No active devices" />
        )}
        {active.map(row)}
        {past.length > 0 && (
          <details className="sec-past">
            <summary>Earlier sign-ins ({past.length})</summary>
            {past.map(row)}
          </details>
        )}
      </div>
    </section>
  );
}
