import { Fragment, useLayoutEffect, useRef, useState } from 'react';
import {
  inlineRuns, insertDivider, parseBlocks, setLinePrefix, toggleInline,
} from '../descriptionFormat';

function Inline({ text }) {
  return inlineRuns(text).map((run, i) => {
    if (run.kind === 'bold') return <strong key={i}>{run.text}</strong>;
    if (run.kind === 'italic') return <em key={i}>{run.text}</em>;
    return <Fragment key={i}>{run.text}</Fragment>;
  });
}

/** The formatted description as a traveller will see it. Built from elements, never raw HTML. */
export function DescriptionPreview({ value }) {
  const blocks = parseBlocks(value);
  if (!blocks.length) return <div className="rte-empty">Nothing to preview yet.</div>;
  return (
    <div className="rte-preview">
      {blocks.map((b, i) => {
        if (b.type === 'heading') {
          const Tag = `h${b.level}`;
          return <Tag key={i}><Inline text={b.text} /></Tag>;
        }
        if (b.type === 'divider') return <hr key={i} />;
        if (b.type === 'ul' || b.type === 'ol') {
          const List = b.type;
          return <List key={i}>{b.items.map((t, j) => <li key={j}><Inline text={t} /></li>)}</List>;
        }
        return (
          <p key={i}>
            {b.lines.map((l, j) => (
              <Fragment key={j}>{j > 0 && <br />}<Inline text={l} /></Fragment>
            ))}
          </p>
        );
      })}
    </div>
  );
}

const TOOLS = [
  { id: 'h2', label: 'Heading', title: 'Heading for the selected line' },
  { id: 'h3', label: 'Subheading', title: 'Smaller heading for the selected line' },
  { id: 'bold', label: 'B', title: 'Bold (Ctrl+B)', className: 'rte-bold' },
  { id: 'italic', label: 'I', title: 'Italic (Ctrl+I)', className: 'rte-italic' },
  { id: 'ul', label: '• List', title: 'Bulleted list' },
  { id: 'ol', label: '1. List', title: 'Numbered list' },
  { id: 'hr', label: 'Line', title: 'Dividing line' },
];

/**
 * A description box with Word-style buttons. Select text, press a button, and it
 * is formatted; "Preview" shows what the traveller will see. The text itself is
 * saved as light Markdown (see descriptionFormat.js), which the app renders.
 */
export default function DescriptionEditor({ value, onChange, rows = 10, placeholder }) {
  const ref = useRef(null);
  const nextSelection = useRef(null);
  const [mode, setMode] = useState('write');
  const text = value || '';

  // After a toolbar edit the textarea re-renders; put the selection back.
  useLayoutEffect(() => {
    const sel = nextSelection.current;
    if (!sel || !ref.current) return;
    nextSelection.current = null;
    ref.current.focus();
    ref.current.setSelectionRange(sel.start, sel.end);
  }, [text]);

  const apply = (id) => {
    const el = ref.current;
    if (!el) return;
    const state = { value: text, start: el.selectionStart, end: el.selectionEnd };
    const result = id === 'bold' ? toggleInline(state, '**', 'bold text')
      : id === 'italic' ? toggleInline(state, '*', 'italic text')
      : id === 'hr' ? insertDivider(state)
      : setLinePrefix(state, id);
    nextSelection.current = { start: result.start, end: result.end };
    onChange(result.value);
  };

  const onKeyDown = (e) => {
    if (!(e.ctrlKey || e.metaKey) || e.altKey) return;
    const key = e.key.toLowerCase();
    if (key === 'b' || key === 'i') {
      e.preventDefault();
      apply(key === 'b' ? 'bold' : 'italic');
    }
  };

  return (
    <div className="rte">
      <div className="rte-bar">
        <div className="rte-tools" role="toolbar" aria-label="Formatting">
          {TOOLS.map((t) => (
            <button
              key={t.id} type="button" title={t.title} disabled={mode !== 'write'}
              className={`rte-btn ${t.className || ''}`}
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => apply(t.id)}
            >
              {t.label}
            </button>
          ))}
        </div>
        <div className="rte-tabs">
          <button type="button" className={mode === 'write' ? 'is-on' : ''} onClick={() => setMode('write')}>Write</button>
          <button type="button" className={mode === 'preview' ? 'is-on' : ''} onClick={() => setMode('preview')}>Preview</button>
        </div>
      </div>
      {mode === 'write' ? (
        <textarea
          ref={ref} className="form-textarea rte-text" rows={rows} value={text}
          placeholder={placeholder} onKeyDown={onKeyDown}
          onChange={(e) => onChange(e.target.value)}
        />
      ) : (
        <DescriptionPreview value={text} />
      )}
    </div>
  );
}
