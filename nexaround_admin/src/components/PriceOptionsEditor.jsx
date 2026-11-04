// Every price a package is sold at: "LKR 30,000 / group (max 7)" or
// "LKR 8,000 / person (min 3)". The same file lives in nexaround_admin and
// nexaround_partner; keep the two copies identical. The partner portal passes
// withUsd={false}: only NexAround sets the dollar price and the commission.
// In both, a row's amount is what the vendor gets; the admin panel shows the
// traveller's price beside it, worked out with `commission` (a percentage),
// as the server's experience_format.with_commission does.

// The server's experience_format.OPTION_BASES and MAX_PRICE_OPTIONS.
const OPTION_BASES = [
  { value: 'per_person', label: 'Per person' },
  { value: 'per_group', label: 'Per group' },
  { value: 'per_hour', label: 'Per hour' },
  { value: 'from', label: 'Starting from' },
];
export const MAX_PRICE_OPTIONS = 6;

const blankRow = () => ({ id: null, amount: '', usd: '', basis: 'per_person', min_people: '', max_people: '' });
const blankToNull = (v) => (v === '' || v == null ? null : Number(v));

/** The traveller's price for a vendor's amount: "12000" at 25 -> 15000. */
export const withCommission = (amount, percent) => (
  Math.round(Number(amount) * (1 + (Number(percent) || 0) / 100) * 100) / 100
);

/** The package's options as form rows (numbers become strings). A new package starts with one blank row. */
export const optionsToRows = (options) => (options?.length ? options : [blankRow()]).map((o) => ({
  id: o.id ?? null,
  // The vendor's amount: the admin's options carry it as vendor_amount, the
  // partner portal's (and options from before commissions) as amount.
  amount: o.vendor_amount ?? o.amount ?? '',
  usd: o.usd ?? '',
  basis: o.basis || 'per_person',
  min_people: o.min_people ?? '',
  max_people: o.max_people ?? '',
}));

/** Rows with no price are dropped; none left means "Price on request".
 * The admin panel sends the vendor's amount as vendor_amount (the server works
 * out the traveller's price); the partner portal sends it as amount. */
export const rowsToOptions = (rows, withUsd) => rows
  .filter((r) => r.amount !== '' && r.amount != null)
  .map((r) => ({
    id: r.id,
    ...(withUsd ? { vendor_amount: Number(r.amount), usd: blankToNull(r.usd) } : { amount: Number(r.amount) }),
    basis: r.basis,
    min_people: blankToNull(r.min_people),
    max_people: blankToNull(r.max_people),
  }));

export default function PriceOptionsEditor({ rows, onChange, currency, withUsd, packageMax, commission }) {
  const patchRow = (index, patch) => onChange(rows.map((r, i) => (i === index ? { ...r, ...patch } : r)));
  const removeRow = (index) => onChange(rows.filter((_, i) => i !== index));
  const inDollars = currency === 'USD';
  const code = currency || 'LKR';
  const money = (v) => `${code} ${Number(v).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;

  return (
    <div className="price-options">
      {rows.map((row, index) => (
        <div className="price-option" key={row.id || `new-${index}`}>
          <div className="price-option-head">
            <span>{index === 0 ? 'Main price' : `Option ${index + 1}`}</span>
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => removeRow(index)}>Remove</button>
          </div>
          <div className={`price-option-grid ${withUsd ? 'with-usd' : ''}`}>
            <div className="form-group">
              <label className="form-label">{withUsd ? `Vendor gets (${code})` : `You receive (${code})`}</label>
              <input
                type="number" step="0.01" min="0" className="form-input" placeholder="30000"
                value={row.amount} onChange={(e) => patchRow(index, { amount: e.target.value })}
              />
            </div>
            {withUsd && (
              <div className="form-group">
                <label className="form-label">Traveller price in USD</label>
                <input
                  type="number" step="0.01" min="0" className="form-input" placeholder="90"
                  value={row.usd} disabled={inDollars}
                  title={inDollars ? 'The price is in dollars already' : undefined}
                  onChange={(e) => patchRow(index, { usd: e.target.value })}
                />
              </div>
            )}
            <div className="form-group">
              <label className="form-label">Basis</label>
              <select
                className="form-select" value={row.basis}
                onChange={(e) => patchRow(index, { basis: e.target.value })}
              >
                {OPTION_BASES.map((b) => <option key={b.value} value={b.value}>{b.label}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">Min people</label>
              <input
                type="number" min="1" className="form-input" placeholder="1"
                value={row.min_people} onChange={(e) => patchRow(index, { min_people: e.target.value })}
              />
            </div>
            <div className="form-group">
              <label className="form-label">Max people</label>
              <input
                type="number" min="1" className="form-input" placeholder={packageMax ? String(packageMax) : 'Any'}
                value={row.max_people} onChange={(e) => patchRow(index, { max_people: e.target.value })}
              />
            </div>
          </div>
          {withUsd && row.amount !== '' && row.amount != null && (
            <div className="price-option-split">
              Traveller pays <strong>{money(withCommission(row.amount, commission))}</strong>
              {' · '}commission {money(withCommission(row.amount, commission) - Number(row.amount))}
              {' '}({Number(commission) || 0}%)
            </div>
          )}
        </div>
      ))}
      {rows.length === 0 && (
        <div className="price-options-empty">No price: travellers see “Price on request”.</div>
      )}
      {rows.length < MAX_PRICE_OPTIONS && (
        <button type="button" className="btn btn-ghost btn-sm" onClick={() => onChange([...rows, blankRow()])}>
          + Add price option
        </button>
      )}
    </div>
  );
}
