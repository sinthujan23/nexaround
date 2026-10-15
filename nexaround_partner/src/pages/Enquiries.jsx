import { useEffect, useState } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { useApi, apiGet } from '../api';
import { RESYNC, useLiveEvent } from '../live';
import { InboxIcon, RefreshIcon } from '../components/Icons';
import { Avatar } from '../components/Kit';
import {
  EmptyState, EnquiryStatusPill, ErrorBanner, ListRow, Loader, Pagination, SearchInput, Tabs,
} from '../components/Lists';
import {
  ENQUIRY_STATUSES, STATUS_LABELS, formatDateTime, formatAge, formatDay, guestsLabel,
} from '../format';
import EnquiryDetail from './EnquiryDetail';

const PAGE_SIZE = 50;

/**
 * The inbox. The open enquiry, the status filter and the page are all in the
 * URL (/enquiries/:id?status=new&page=2), so a refresh, the Back button and a
 * link from the bell or the dashboard land in the same place.
 */
export default function Enquiries() {
  const { enquiryId } = useParams();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const status = params.get('status') || '';
  const page = Math.max(1, Number(params.get('page')) || 1);

  const [search, setSearch] = useState('');
  const [counts, setCounts] = useState({});
  const [countsVersion, setCountsVersion] = useState(0);

  const { data, error, refetch } = useApi(
    `/partner/enquiries?page=${page}&page_size=${PAGE_SIZE}${status ? `&status=${status}` : ''}`
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

  const refresh = () => {
    refetch();
    setCountsVersion((n) => n + 1);
  };

  // A new enquiry, or a status changed in another tab, by another login or by
  // NexAround: the list and counts follow. (The open enquiry follows itself.)
  useLiveEvent(['enquiry.created', 'enquiry.updated', RESYNC], refresh);

  // Search only narrows the page already loaded.
  const q = search.trim().toLowerCase();
  const enquiries = rawEnquiries.filter((e) =>
    !q || [e.contact_name, e.contact_phone, e.contact_email, e.package_title_snapshot]
      .some((f) => (f || '').toLowerCase().includes(q))
  );

  // Keep the filter and page when moving between enquiries.
  const keep = params.toString() ? `?${params}` : '';
  const open = (id) => navigate(`/enquiries/${id}${keep}`);
  const close = () => navigate(`/enquiries${keep}`);

  const setQuery = (changes) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(changes)) {
      if (v) next.set(k, v); else next.delete(k);
    }
    setParams(next);
  };

  const filters = [
    { value: '', label: 'All', count: counts.all },
    ...ENQUIRY_STATUSES.map((s) => ({ value: s, label: STATUS_LABELS[s], dot: s, count: counts[s] })),
  ];

  return (
    <>
      <div className="xp-toolbar">
        <Tabs items={filters} value={status} onChange={(value) => setQuery({ status: value, page: '' })} />
        <div className="xp-toolbar-right">
          <SearchInput value={search} onChange={setSearch} placeholder="Search name, phone, package…" />
          <button className="btn btn-ghost btn-sm" onClick={refresh} title="Refresh">
            <RefreshIcon size={15} /> Refresh
          </button>
        </div>
      </div>

      <ErrorBanner>{error}</ErrorBanner>

      <div className={`xp-split ${enquiryId ? 'has-selection' : ''}`}>
        <aside className="xp-pane xp-list-pane">
          <div className="xp-list-body">
            {!data && !error && <Loader />}

            {data && enquiries.length === 0 && (
              <EmptyState icon={InboxIcon} title={search || status ? 'Nothing matches' : 'No enquiries yet'}>
                {search || status
                  ? 'Try another status or search.'
                  : 'They arrive here as soon as a traveller asks about one of your packages.'}
              </EmptyState>
            )}

            {enquiries.map((e) => (
              <ListRow
                key={e.id}
                variant="xp"
                active={enquiryId === e.id}
                onClick={() => open(e.id)}
                lead={<Avatar name={e.contact_name} />}
                title={e.contact_name}
                strong={e.status === 'new'}
                subs={[
                  <span key="p" style={{ color: 'var(--text-primary)' }}>{e.package_title_snapshot || 'General enquiry'}</span>,
                  [guestsLabel(e.party_size), formatDay(e.preferred_date)].filter(Boolean).join(' · ') || 'No date or party size given',
                ]}
                side={(
                  <>
                    <span title={formatDateTime(e.created_at)}>{formatAge(e.created_at)}</span>
                    <EnquiryStatusPill status={e.status} />
                  </>
                )}
              />
            ))}
          </div>

          <Pagination
            className="xp-list-foot" page={page} totalPages={totalPages}
            onPage={(p) => setQuery({ page: p > 1 ? String(p) : '' })}
          />
        </aside>

        <section className="xp-pane xp-detail-pane">
          {enquiryId ? (
            <EnquiryDetail key={enquiryId} id={enquiryId} onClose={close} onChanged={refresh} />
          ) : (
            <EmptyState icon={InboxIcon} title="Select an enquiry" pad={32}>
              {counts.new
                ? `${counts.new} new ${counts.new === 1 ? 'enquiry is' : 'enquiries are'} waiting for your reply.`
                : 'The traveller’s request and contact details open here.'}
            </EmptyState>
          )}
        </section>
      </div>
    </>
  );
}
