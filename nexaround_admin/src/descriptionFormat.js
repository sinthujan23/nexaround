// The light formatting a package description can carry, as Markdown:
//   ## Heading   ### Subheading   **bold**   *italic*   - bullet   1. numbered   ---
// The editor writes it, the preview below shows it, and the app renders the same
// text. Keep the three in step: nothing here may produce a symbol the app cannot
// draw. (nexaround_partner/src/descriptionFormat.js is an identical copy.)

const HEADING = /^#{1,6}\s+/;
const BULLET = /^[-*+]\s+/;
const NUMBERED = /^\d+\.\s+/;
const DIVIDER = /^\s*([-*_])(\s*\1){2,}\s*$/;
const INLINE = /\*\*(?=\S)(.+?)(?<=\S)\*\*|(?<![*\w])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![*\w])/g;

/** Split a line into plain / bold / italic runs: `[{ kind, text }]`. */
export function inlineRuns(line) {
  const runs = [];
  let last = 0;
  for (const m of line.matchAll(INLINE)) {
    if (m.index > last) runs.push({ kind: 'text', text: line.slice(last, m.index) });
    runs.push(m[1] !== undefined ? { kind: 'bold', text: m[1] } : { kind: 'italic', text: m[2] });
    last = m.index + m[0].length;
  }
  if (last < line.length) runs.push({ kind: 'text', text: line.slice(last) });
  return runs;
}

/**
 * The description as blocks for the preview: `heading` {level, text},
 * `paragraph` {lines}, `ul` / `ol` {items}, `divider`. A single line break stays
 * a line break (the app does the same), a blank line starts a new block.
 */
export function parseBlocks(text) {
  const blocks = [];
  let current = null;
  const flush = () => { current = null; };

  for (const raw of (text || '').replace(/\r\n/g, '\n').split('\n')) {
    const line = raw.trimEnd();
    if (!line.trim()) { flush(); continue; }
    if (DIVIDER.test(line)) { blocks.push({ type: 'divider' }); flush(); continue; }

    const heading = line.match(/^\s{0,3}(#{1,6})\s+(.*)$/);
    if (heading) {
      blocks.push({ type: 'heading', level: Math.min(heading[1].length, 3), text: heading[2] });
      flush();
      continue;
    }
    const bullet = line.match(/^\s*[-*+]\s+(.*)$/);
    const numbered = line.match(/^\s*\d+\.\s+(.*)$/);
    const item = bullet || numbered;
    if (item) {
      const type = bullet ? 'ul' : 'ol';
      if (!current || current.type !== type) {
        current = { type, items: [] };
        blocks.push(current);
      }
      current.items.push(item[1]);
      continue;
    }
    if (!current || current.type !== 'paragraph') {
      current = { type: 'paragraph', lines: [] };
      blocks.push(current);
    }
    current.lines.push(line);
  }
  return blocks;
}

// --- Toolbar edits -----------------------------------------------------------
// Each takes { value, start, end } (the text and its selection) and returns the
// same shape, so they can be tried without a browser.

/** Wrap the selection in `marker` (`**` or `*`), or take the marker off again. */
export function toggleInline({ value, start, end }, marker, placeholder) {
  // Markers hug the words: "** bold **" would not be bold.
  while (start < end && /\s/.test(value[start])) start += 1;
  while (end > start && /\s/.test(value[end - 1])) end -= 1;

  const m = marker.length;
  const before = value.slice(0, start);
  const selected = value.slice(start, end);
  const after = value.slice(end);

  if (!selected) {
    const text = `${before}${marker}${placeholder}${marker}${after}`;
    return { value: text, start: start + m, end: start + m + placeholder.length };
  }
  // A single * must not mistake the edge of a ** pair for its own marker.
  const notPartOfBold = marker !== '*' || (!before.endsWith('**') && !after.startsWith('**'));
  if (before.endsWith(marker) && after.startsWith(marker) && notPartOfBold) {
    return { value: before.slice(0, -m) + selected + after.slice(m), start: start - m, end: end - m };
  }
  if (selected.length > 2 * m && selected.startsWith(marker) && selected.endsWith(marker)
      && (marker !== '*' || !selected.startsWith('**'))) {
    const inner = selected.slice(m, -m);
    return { value: before + inner + after, start, end: start + inner.length };
  }
  return { value: `${before}${marker}${selected}${marker}${after}`, start: start + m, end: end + m };
}

const PREFIXES = {
  h2: { add: () => '## ', has: (l) => /^##\s+/.test(l) && !/^###/.test(l) },
  h3: { add: () => '### ', has: (l) => /^###\s+/.test(l) },
  ul: { add: () => '- ', has: (l) => BULLET.test(l) },
  ol: { add: (n) => `${n}. `, has: (l) => NUMBERED.test(l) },
};
const stripBlockPrefix = (l) => l.replace(HEADING, '').replace(BULLET, '').replace(NUMBERED, '');

/** Turn the selected lines into a heading / bullet list / numbered list, or back to plain. */
export function setLinePrefix({ value, start, end }, kind) {
  const spec = PREFIXES[kind];
  const from = value.lastIndexOf('\n', start - 1) + 1;
  let to = value.indexOf('\n', end > start ? end - 1 : end);
  if (to === -1) to = value.length;

  const lines = value.slice(from, to).split('\n');
  const filled = lines.filter((l) => l.trim());
  const allHave = filled.length > 0 && filled.every(spec.has);

  let n = 0;
  const next = lines.map((l) => {
    if (!l.trim()) return l;
    const plain = stripBlockPrefix(l);
    if (allHave) return plain;
    n += 1;
    return spec.add(n) + plain;
  });
  const block = next.join('\n');
  return { value: value.slice(0, from) + block + value.slice(to), start: from, end: from + block.length };
}

/** A dividing line on its own, with a blank line either side. */
export function insertDivider({ value, start, end }) {
  const before = value.slice(0, start).replace(/\n+$/, '');
  const after = value.slice(end).replace(/^\n+/, '');
  const head = before ? `${before}\n\n---\n\n` : '---\n\n';
  return { value: head + after, start: head.length, end: head.length };
}
