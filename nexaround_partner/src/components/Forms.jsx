// The form pieces Packages, Profile and the auth pages each wrote out by hand
// (a `.form-group`, a label, an input - about twenty-five times).

/** A label, the control, and optional help text. */
export function Field({ label, hint, className = '', children }) {
  return (
    <div className={`form-group ${className}`}>
      {label && <label className="form-label">{label}</label>}
      {children}
      {hint && <div className="form-hint">{hint}</div>}
    </div>
  );
}

/** A single-line input. `onChange` receives the new value, not the event. */
export function TextField({ label, hint, value, onChange, className, ...input }) {
  return (
    <Field label={label} hint={hint} className={className}>
      <input
        type="text" className="form-input" value={value ?? ''}
        onChange={(e) => onChange(e.target.value)} {...input}
      />
    </Field>
  );
}

export function TextArea({ label, hint, value, onChange, rows = 4, className, ...input }) {
  return (
    <Field label={label} hint={hint} className={className}>
      <textarea
        className="form-textarea" rows={rows} value={value ?? ''}
        onChange={(e) => onChange(e.target.value)} {...input}
      />
    </Field>
  );
}

/** `options` is `[{ value, label }]`. */
export function SelectField({ label, hint, value, onChange, options, className, ...select }) {
  return (
    <Field label={label} hint={hint} className={className}>
      <select
        className="form-select" value={value ?? ''}
        onChange={(e) => onChange(e.target.value)} {...select}
      >
        {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </Field>
  );
}

/** Fields side by side: `cols` is 2 or 3. */
export function FieldGrid({ cols = 2, children }) {
  return <div className={`form-grid-${cols}`}>{children}</div>;
}

/**
 * The bar under a form: whether there is anything unsaved, then Discard and
 * Save. `left` replaces the status text (a package puts its visibility switch
 * there); `extra` adds buttons before Discard (Delete, Cancel).
 */
export function SaveBar({
  dirty, saving, busy = false, onSave, onDiscard, saveLabel = 'Save changes', left, extra, submit = false,
}) {
  return (
    <div className="xp-savebar">
      {left || (dirty
        ? <span className="unsaved"><span className="dot dot-new" /> Unsaved changes</span>
        : <span>All changes saved</span>)}
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        {extra}
        {dirty && onDiscard && (
          <button type="button" className="btn btn-ghost btn-sm" onClick={onDiscard}>Discard</button>
        )}
        <button
          type={submit ? 'submit' : 'button'} className="btn btn-primary btn-sm"
          disabled={!dirty || saving || busy} onClick={submit ? undefined : onSave}
        >
          {busy ? 'Uploading photos…' : saving ? 'Saving…' : saveLabel}
        </button>
      </div>
    </div>
  );
}
