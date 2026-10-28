// The Word-style editor (components/RichTextEditor.jsx) edits a TipTap
// document; guides store light Markdown, the same subset the description
// editor writes and the app renders (descriptionFormat.js):
//   ## Heading   ### Subheading   **bold**   *italic*   - bullet   1. numbered   ---
// These two functions convert between them. Anything else pasted in (links,
// tables, colours) never reaches the text: the editor's schema has no place
// for it, and what is left is written back as the subset above.

import { inlineRuns, parseBlocks } from './descriptionFormat';

const inlineNodes = (text) => inlineRuns(text)
  .filter((run) => run.text)
  .map((run) => (run.kind === 'text'
    ? { type: 'text', text: run.text }
    : { type: 'text', text: run.text, marks: [{ type: run.kind }] }));

const paragraph = (lines) => ({
  type: 'paragraph',
  content: lines.flatMap((line, i) => [...(i ? [{ type: 'hardBreak' }] : []), ...inlineNodes(line)]),
});

/** Light Markdown → the editor's document. */
export function markdownToDoc(markdown) {
  const content = parseBlocks(markdown || '').map((b) => {
    if (b.type === 'heading') {
      return { type: 'heading', attrs: { level: b.level === 3 ? 3 : 2 }, content: inlineNodes(b.text) };
    }
    if (b.type === 'divider') return { type: 'horizontalRule' };
    if (b.type === 'ul' || b.type === 'ol') {
      return {
        type: b.type === 'ul' ? 'bulletList' : 'orderedList',
        content: b.items.map((t) => ({ type: 'listItem', content: [{ type: 'paragraph', content: inlineNodes(t) }] })),
      };
    }
    return paragraph(b.lines);
  });
  return { type: 'doc', content: content.length ? content : [{ type: 'paragraph' }] };
}

// A run's marker: bold wins over italic, since the subset has no "both".
const markerOf = (node) => {
  const marks = (node.marks || []).map((m) => m.type);
  return marks.includes('bold') ? '**' : marks.includes('italic') ? '*' : '';
};

/** A block's text with its bold and italic, line breaks kept as "\n". */
function inlineMarkdown(nodes = []) {
  // Neighbouring pieces with the same marker are one run, so "**a****b**"
  // cannot happen; a line break always ends a run (markers never span lines).
  const runs = [];
  for (const node of nodes) {
    if (node.type === 'hardBreak') {
      runs.push({ marker: null, text: '\n' });
      continue;
    }
    if (node.type !== 'text' || !node.text) continue;
    const marker = markerOf(node);
    const last = runs[runs.length - 1];
    if (last && last.marker === marker) last.text += node.text;
    else runs.push({ marker, text: node.text });
  }
  return runs.map(({ marker, text }) => {
    if (!marker) return text;
    // Markers hug the words: "** bold **" would not be bold.
    const [, lead, core, trail] = text.match(/^(\s*)([\s\S]*?)(\s*)$/);
    return core ? `${lead}${marker}${core}${marker}${trail}` : text;
  }).join('');
}

function listItems(list) {
  const items = [];
  for (const item of list.content || []) {
    for (const child of item.content || []) {
      if (child.type === 'paragraph') {
        const text = inlineMarkdown(child.content).replace(/\s*\n\s*/g, ' ').trim();
        if (text) items.push(text);
      } else if (child.type === 'bulletList' || child.type === 'orderedList') {
        // The app shows one level of list: a nested one joins its parent's.
        items.push(...listItems(child));
      }
    }
  }
  return items;
}

/** The editor's document → light Markdown. */
export function docToMarkdown(doc) {
  const blocks = [];
  for (const node of doc?.content || []) {
    if (node.type === 'heading') {
      const text = inlineMarkdown(node.content).replace(/\s*\n\s*/g, ' ').trim();
      if (text) blocks.push(`${node.attrs?.level === 3 ? '###' : '##'} ${text}`);
    } else if (node.type === 'horizontalRule') {
      blocks.push('---');
    } else if (node.type === 'bulletList' || node.type === 'orderedList') {
      const items = listItems(node);
      if (items.length) {
        blocks.push(items.map((t, i) => `${node.type === 'bulletList' ? '-' : `${i + 1}.`} ${t}`).join('\n'));
      }
    } else {
      const text = inlineMarkdown(node.content).split('\n').map((l) => l.trim()).join('\n').trim();
      if (text) blocks.push(text);
    }
  }
  return blocks.join('\n\n');
}
