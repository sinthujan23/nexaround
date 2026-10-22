// Every price a package is sold at: "LKR 30,000 / group (max 7)" or
// "LKR 8,000 / person (min 3)". The same file lives in nexaround_admin and
// nexaround_partner; keep the two copies identical. The partner portal passes
// withUsd={false}: only NexAround sets the dollar price.

// The server's experience_format.PRICE_BASES and MAX_PRICE_OPTIONS.
const OPTION_BASES = [
  { value: 'per_person', label: 'Per person' },
  { value: 'per_group', label: 'Per group' },
  { value: 'from', label: 'Starting from' },
];
export const MAX_PRICE_OPTIONS = 6;

const blankRow = () => ({ id: null, amount: '', usd: '', basis: 'per_person', min_people: '', max_people: '' });
const blankToNull = (v) => (v === '' || v == null ? null : Number(v));

/** The package's options as form rows (numbers become strings). A new package starts with one blank row. */
export const optionsToRows = (options) => (options?.length ? options : [blankRow()]).map((o) => ({
  id: o.id ?? null,
  amount: o.amount ?? '',
  usd: o.usd ?? '',
  basis: o.basis || 'per_person',
  min_people: o.min_people ?? '',
  max_people: o.max_people ?? '',
}));

/** Rows with no price are dropped; none left means "Price on request". */
export const rowsToOptions = (rows, withUsd) => rows
  .filter((r) => r.amount !== '' && r.amount != null)
  .map((r) => ({
    id: r.id,
    amount: Number(r.amount),
    ...(withUsd ? { usd: blankToNull(r.usd) } : {}),
    basis: r.basis,
    min_people: blankToNull(r.min_people),
    max_people: blankToNull(r.max_people),
  }));

export default function PriceOptionsEditor({ rows, onChange, currency, withUsd, packageMax }) {
  const patchRow = (index, patch) => onChange(rows.map((r, i) => (i === index ? { ...r, ...patch } : r)));
  const removeRow = (index) => onChange(rows.filter((_, i) => i !== index));
  const inDollars = currency === 'USD';

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
              <label className="form-label">Price ({currency || 'LKR'})</label>
              <input
                type="number" step="0.01" min="0" className="form-input" placeholder="30000"
                value={row.amount} onChange={(e) => patchRow(index, { amount: e.target.value })}
              />
            </div>
            {withUsd && (
              <div className="form-group">
                <label className="form-label">Price in USD</label>
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
