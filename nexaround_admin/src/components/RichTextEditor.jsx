import { useEffect, useRef } from 'react';
import { EditorContent, useEditor, useEditorState } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import { docToMarkdown, markdownToDoc } from '../markdownDoc';

// Only what the app can draw: two heading sizes, bold, italic, lists and a
// dividing line. No links (partner links have their own buttons), no colours.
const EXTENSIONS = [
  StarterKit.configure({
    heading: { levels: [2, 3] },
    blockquote: false,
    code: false,
    codeBlock: false,
    strike: false,
    underline: false,
    link: false,
  }),
];

const TOOLS = [
  { id: 'h2', label: 'Heading', title: 'Heading', run: (c) => c.toggleHeading({ level: 2 }) },
  { id: 'h3', label: 'Subheading', title: 'Smaller heading', run: (c) => c.toggleHeading({ level: 3 }) },
  { id: 'bold', label: 'B', title: 'Bold (Ctrl+B)', className: 'rte-bold', run: (c) => c.toggleBold() },
  { id: 'italic', label: 'I', title: 'Italic (Ctrl+I)', className: 'rte-italic', run: (c) => c.toggleItalic() },
  { id: 'ul', label: '• List', title: 'Bulleted list', run: (c) => c.toggleBulletList() },
  { id: 'ol', label: '1. List', title: 'Numbered list', run: (c) => c.toggleOrderedList() },
  { id: 'hr', label: 'Line', title: 'Dividing line', run: (c) => c.setHorizontalRule() },
];

/**
 * A Word-style text box: what you type is formatted as you type it, with
 * buttons for headings, bold, italic and lists. It saves light Markdown (see
 * markdownDoc.js), the same text the app renders.
 */
export default function RichTextEditor({ value, onChange, placeholder, minHeight = 140 }) {
  // The Markdown this editor last handed out. A `value` that differs came from
  // outside (Discard, another guide opened) and replaces the text.
  const emitted = useRef(value || '');
  const onChangeRef = useRef(onChange);
  useEffect(() => { onChangeRef.current = onChange; });

  const editor = useEditor({
    extensions: EXTENSIONS,
    content: markdownToDoc(value || ''),
    editorProps: { attributes: { class: 'wte-doc' } },
    onUpdate: ({ editor: e }) => {
      const markdown = docToMarkdown(e.getJSON());
      emitted.current = markdown;
      onChangeRef.current(markdown);
    },
  });

  useEffect(() => {
    if (!editor || (value || '') === emitted.current) return;
    emitted.current = value || '';
    editor.commands.setContent(markdownToDoc(value || ''), { emitUpdate: false });
  }, [editor, value]);

  const state = useEditorState({
    editor,
    selector: ({ editor: e }) => (e ? {
      h2: e.isActive('heading', { level: 2 }),
      h3: e.isActive('heading', { level: 3 }),
      bold: e.isActive('bold'),
      italic: e.isActive('italic'),
      ul: e.isActive('bulletList'),
      ol: e.isActive('orderedList'),
      canUndo: e.can().undo(),
      canRedo: e.can().redo(),
      empty: e.isEmpty,
    } : null),
  }) || {};

  const apply = (tool) => {
    if (!editor) return;
    tool.run(editor.chain().focus()).run();
  };

  return (
    <div className="wte">
      <div className="wte-bar" role="toolbar" aria-label="Formatting">
        {TOOLS.map((t) => (
          <button
            key={t.id} type="button" title={t.title}
            className={`rte-btn ${t.className || ''} ${state[t.id] ? 'is-on' : ''}`}
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => apply(t)}
          >
            {t.label}
          </button>
        ))}
        <span className="wte-gap" />
        <button
          type="button" className="rte-btn" title="Undo (Ctrl+Z)" disabled={!state.canUndo}
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => editor?.chain().focus().undo().run()}
        >
          ↶
        </button>
        <button
          type="button" className="rte-btn" title="Redo (Ctrl+Y)" disabled={!state.canRedo}
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => editor?.chain().focus().redo().run()}
        >
          ↷
        </button>
      </div>
      <div className="wte-page" style={{ minHeight }}>
        {state.empty && placeholder && <div className="wte-placeholder">{placeholder}</div>}
        <EditorContent editor={editor} />
      </div>
    </div>
  );
}
