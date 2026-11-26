"""support@nexaround.com's mailbox for the admin panel's Support inbox.

The mailbox lives at Hostinger. It is read and changed live over IMAP, with the
same login the backend already sends mail with (SMTP_USER / SMTP_PASSWORD).
Nothing is copied into our database, so the panel and Hostinger webmail always
show the same mails, read marks and folders.

Mails are addressed by folder + IMAP UID. A UID stays the same for as long as
the mail stays in its folder; moving it (Delete, Not spam) gives it a new one
in the other folder.

imaplib is blocking, so every public function here is sync: callers run them
with asyncio.to_thread. Each call opens its own connection (about 0.8 s to
sign in) and closes it again.
"""
from __future__ import annotations

import base64
import html as html_lib
import imaplib
import logging
import re
import smtplib
import ssl
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from email import policy
from email.message import EmailMessage, Message
from email.parser import BytesHeaderParser, BytesParser
from email.utils import formataddr, format_datetime, getaddresses, make_msgid, parsedate_to_datetime
from typing import Iterator, Optional

from app.core.config import settings

logger = logging.getLogger(__name__)

PAGE_SIZE = 50
# The folders the panel shows or moves mails to.
# "system" holds copies of the mails the app sends by itself (codes, booking
# updates, partner links); see email_service._send_smtp_sync.
FOLDERS = ("inbox", "sent", "junk", "trash", "system")
# Moves the panel offers: Delete from any shown folder, and Not spam.
MOVES = {
    ("inbox", "trash"), ("sent", "trash"), ("junk", "trash"), ("junk", "inbox"), ("system", "trash"),
    ("trash", "inbox"),
}
# List filters: IMAP search keys for each. "files" also checks each mail's
# structure, since a multipart/mixed header alone doesn't prove a file.
SHOWS = {"all": [], "unread": ["UNSEEN"], "replied": ["ANSWERED"],
         "files": ["HEADER", "Content-Type", "multipart/mixed"]}

# Biggest mail the panel opens, and biggest inline picture it embeds.
_MAX_MESSAGE_BYTES = 30 * 1024 * 1024
_MAX_INLINE_IMAGE = 2 * 1024 * 1024
_MAX_INLINE_TOTAL = 8 * 1024 * 1024
_SNIPPET_BYTES = 4000
_QUOTE_LIMIT = 20000


class MailboxError(Exception):
    """The mailbox could not be reached or refused the request."""


class NotFound(MailboxError):
    """No mail with that UID in that folder (moved, or deleted elsewhere)."""


def configured() -> bool:
    return bool(settings.SMTP_USER and settings.SMTP_PASSWORD and _imap_host())


def address() -> str:
    return (settings.SMTP_USER or "").strip()


def _imap_host() -> str:
    if settings.IMAP_HOST:
        return settings.IMAP_HOST
    host = settings.SMTP_HOST or ""
    return "imap." + host[5:] if host.startswith("smtp.") else ""


# ── Connection and folders ─────────────────────────────────────────────────

@contextmanager
def _connect() -> Iterator[imaplib.IMAP4_SSL]:
    if not configured():
        raise MailboxError("The support mailbox is not set up on the server.")
    try:
        conn = imaplib.IMAP4_SSL(_imap_host(), settings.IMAP_PORT, timeout=20)
        conn.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
    except (imaplib.IMAP4.error, OSError) as e:
        logger.warning("support mailbox: sign-in failed: %s", e)
        raise MailboxError("Couldn't reach the support mailbox. Try again in a moment.") from e
    try:
        yield conn
    except (imaplib.IMAP4.error, OSError) as e:
        logger.warning("support mailbox: %s", e)
        raise MailboxError("The support mailbox didn't answer. Try again in a moment.") from e
    finally:
        try:
            conn.logout()
        except Exception:
            pass


# Folder names by special-use flag, found once per process.
_SPECIAL_USE = {"sent": b"\\sent", "junk": b"\\junk", "trash": b"\\trash"}
_FALLBACK_NAMES = {
    "inbox": "INBOX", "sent": "INBOX.Sent", "junk": "INBOX.Junk", "trash": "INBOX.Trash",
    "system": "INBOX.System",
}
_folder_names: dict[str, str] = {}
_LIST_LINE = re.compile(rb'^\((?P<flags>[^)]*)\) (?:"[^"]*"|NIL) (?P<name>.+)$')


def _folder(conn: imaplib.IMAP4_SSL, key: str) -> str:
    if key not in FOLDERS:
        raise NotFound(f"Unknown folder {key!r}.")
    if key == "inbox":
        return "INBOX"
    if not _folder_names:
        found = {}
        typ, lines = conn.list()
        for line in lines or []:
            if not isinstance(line, bytes):
                continue
            m = _LIST_LINE.match(line)
            if not m:
                continue
            flags = m.group("flags").lower().split()
            name = m.group("name").strip()
            if name.startswith(b'"') and name.endswith(b'"'):
                name = name[1:-1].replace(b'\\"', b'"').replace(b"\\\\", b"\\")
            for k, flag in _SPECIAL_USE.items():
                if flag in flags and k not in found:
                    found[k] = name.decode("utf-8", "replace")
        _folder_names.update({k: found.get(k, v) for k, v in _FALLBACK_NAMES.items()})
    return _folder_names[key]


def _quote(name: str) -> str:
    return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _select(conn: imaplib.IMAP4_SSL, key: str, *, write: bool = False) -> None:
    typ, _ = conn.select(_quote(_folder(conn, key)), readonly=not write)
    if typ != "OK":
        raise MailboxError(f"Couldn't open the {key} folder.")


def _check_uid(uid: str) -> str:
    if not str(uid).isdigit():
        raise NotFound("No such mail.")
    return str(int(uid))


# ── A small reader for imaplib's FETCH answers ─────────────────────────────
# imaplib hands back FETCH answers half-parsed: lines and (text, literal)
# pairs. These join them into one text with each literal replaced by a marker
# and read it as IMAP lists, so mail bodies, BODYSTRUCTURE and flags come out
# as Python values whatever order or shape the server sends them in.

_LITERAL_AT_END = re.compile(rb"\{(\d+)\}$")


def _join(data) -> tuple[bytes, list[bytes]]:
    text = bytearray()
    literals: list[bytes] = []
    for item in data or []:
        if item is None:
            continue
        if isinstance(item, tuple):
            head, literal = item
            m = _LITERAL_AT_END.search(head)
            text += head[: m.start()] if m else head
            text += b"\x00%d\x00" % len(literals)
            literals.append(literal)
        else:
            text += item
        text += b" "
    return bytes(text), literals


class _Reader:
    _STOP = b' ()"\x00'

    def __init__(self, text: bytes, literals: list[bytes]):
        self.text, self.literals, self.pos = text, literals, 0

    def _skip(self) -> None:
        while self.pos < len(self.text) and self.text[self.pos] in b" \r\n":
            self.pos += 1

    def done(self) -> bool:
        self._skip()
        return self.pos >= len(self.text)

    def value(self):
        self._skip()
        t = self.text
        if self.pos >= len(t):
            return None
        c = t[self.pos]
        if c == ord("("):
            self.pos += 1
            out = []
            while not self.done():
                if t[self.pos] == ord(")"):
                    self.pos += 1
                    return out
                out.append(self.value())
            return out
        if c == ord(")"):
            self.pos += 1
            return None
        if c == ord('"'):
            self.pos += 1
            buf = bytearray()
            while self.pos < len(t) and t[self.pos] != ord('"'):
                if t[self.pos] == ord("\\") and self.pos + 1 < len(t):
                    self.pos += 1
                buf.append(t[self.pos])
                self.pos += 1
            self.pos += 1
            return bytes(buf)
        if c == 0:
            end = t.index(b"\x00", self.pos + 1)
            literal = self.literals[int(t[self.pos + 1:end])]
            self.pos = end + 1
            return literal
        start = self.pos
        while self.pos < len(t) and t[self.pos] not in self._STOP:
            if t[self.pos] == ord("["):
                # A section such as BODY[HEADER.FIELDS (FROM TO)] stays whole.
                close = t.find(b"]", self.pos)
                self.pos = close + 1 if close != -1 else len(t)
                continue
            self.pos += 1
        atom = t[start:self.pos]
        return None if atom.upper() == b"NIL" else atom


def _fetch_key(key: bytes) -> str:
    k = key.upper()
    if k.startswith(b"BODY[HEADER"):
        return "HEADER"
    if k.startswith(b"BODY[TEXT]"):
        return "TEXT"
    if k.startswith(b"BODY[]"):
        return "BODY"
    return k.decode("ascii", "replace")


def _fetch(conn: imaplib.IMAP4_SSL, uids: str, items: str) -> dict[int, dict]:
    """UID FETCH, as {uid: {item: value}}."""
    typ, data = conn.uid("FETCH", uids, items)
    if typ != "OK":
        raise MailboxError("The support mailbox refused to send the mails.")
    reader = _Reader(*_join(data))
    out: dict[int, dict] = {}
    while not reader.done():
        reader.value()  # the sequence number
        values = reader.value()
        if not isinstance(values, list):
            continue
        fields = {}
        for i in range(0, len(values) - 1, 2):
            if isinstance(values[i], bytes):
                fields[_fetch_key(values[i])] = values[i + 1]
        uid = fields.get("UID")
        if isinstance(uid, bytes) and uid.isdigit():
            out.setdefault(int(uid), {}).update(fields)
    return out


# ── Reading headers and bodies ─────────────────────────────────────────────

def _header(msg: Message, name: str) -> str:
    try:
        value = msg.get(name)
        return re.sub(r"\s+", " ", str(value)).strip() if value is not None else ""
    except Exception:
        raw = msg.get_all(name, [])
        return str(raw[0]) if raw else ""


def _people(msg: Message, *names: str) -> list[dict]:
    values = []
    for name in names:
        try:
            values += [str(v) for v in msg.get_all(name, [])]
        except Exception:
            continue
    out, seen = [], set()
    for display, addr in getaddresses(values):
        addr = addr.strip()
        if not addr or addr.lower() in seen:
            continue
        seen.add(addr.lower())
        out.append({"name": display.strip(), "email": addr})
    return out


def _date(msg: Message, internal: Optional[bytes] = None) -> Optional[str]:
    raw = _header(msg, "Date")
    if raw:
        try:
            d = parsedate_to_datetime(raw)
            if d.tzinfo is None:
                d = d.replace(tzinfo=timezone.utc)
            return d.astimezone(timezone.utc).isoformat()
        except Exception:
            pass
    if internal:
        try:
            d = datetime.strptime(internal.decode().strip(), "%d-%b-%Y %H:%M:%S %z")
            return d.astimezone(timezone.utc).isoformat()
        except Exception:
            pass
    return None


def _part_text(part: Message) -> str:
    try:
        return part.get_content()
    except Exception:
        payload = part.get_payload(decode=True) or b""
        charset = part.get_content_charset() or "utf-8"
        try:
            return payload.decode(charset, "replace")
        except LookupError:
            return payload.decode("utf-8", "replace")


_BLOCKS = re.compile(r"<(script|style|head|title)\b.*?</\1\s*>", re.I | re.S)
_TAGS = re.compile(r"<[^>]+>")
_BREAKS = re.compile(r"<\s*(br|/p|/div|/tr|/li|/h\d)\b[^>]*>", re.I)


def html_to_text(value: str) -> str:
    value = _BLOCKS.sub(" ", value)
    value = _BREAKS.sub("\n", value)
    value = _TAGS.sub(" ", value)
    value = html_lib.unescape(value)
    lines = [re.sub(r"[ \t ]+", " ", line).strip() for line in value.splitlines()]
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def _snippet(header: bytes, text: bytes) -> str:
    """The opening words of a mail, from its first few KB."""
    try:
        msg = BytesParser(policy=policy.default).parsebytes(header.rstrip(b"\r\n") + b"\r\n\r\n" + text)
        plain = html = None
        for part in msg.walk():
            if part.is_multipart() or part.get_content_disposition() == "attachment":
                continue
            kind = part.get_content_type()
            if kind == "text/plain" and plain is None:
                plain = _part_text(part)
            elif kind == "text/html" and html is None:
                html = _part_text(part)
        body = plain if plain and plain.strip() else html_to_text(html or "")
    except Exception:
        return ""
    # Skip quoted lines from earlier mails in a thread.
    lines = [line for line in body.splitlines() if not line.lstrip().startswith(">")]
    return re.sub(r"\s+", " ", " ".join(lines)).strip()[:180]


def _has_attachment(structure) -> bool:
    if isinstance(structure, list):
        return any(_has_attachment(v) for v in structure)
    return isinstance(structure, bytes) and structure.lower() == b"attachment"


def _summary(uid: int, fields: dict, folder: str) -> dict:
    header = fields.get("HEADER") or b""
    msg = BytesHeaderParser(policy=policy.default).parsebytes(header)
    flags = [f.lower() for f in (fields.get("FLAGS") or []) if isinstance(f, bytes)]
    sender = _people(msg, "From")
    size = fields.get("RFC822.SIZE")
    return {
        "uid": uid,
        "folder": folder,
        "from": sender[0] if sender else None,
        "to": _people(msg, "To", "Cc"),
        "subject": _header(msg, "Subject"),
        "date": _date(msg, fields.get("INTERNALDATE")),
        "snippet": _snippet(header, fields.get("TEXT") or b""),
        "unread": b"\\seen" not in flags,
        "answered": b"\\answered" in flags,
        "has_attachments": _has_attachment(fields.get("BODYSTRUCTURE")),
        "size": int(size) if isinstance(size, bytes) and size.isdigit() else None,
    }


# ── Public: list, count, read ──────────────────────────────────────────────

_LIST_ITEMS = (
    "(UID FLAGS INTERNALDATE RFC822.SIZE BODYSTRUCTURE "
    "BODY.PEEK[HEADER.FIELDS (FROM TO CC SUBJECT DATE CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] "
    f"BODY.PEEK[TEXT]<0.{_SNIPPET_BYTES}>)"
)


def list_messages(folder: str, page: int = 1, query: str = "", show: str = "all") -> dict:
    """One page of a folder, newest first, optionally only mails matching
    `query` anywhere in their headers or text, and only those `show` picks
    (all, unread, replied or files)."""
    page = max(1, page)
    keys = SHOWS.get(show)
    if keys is None:
        raise MailboxError("Unknown filter.")
    with _connect() as conn:
        _select(conn, folder)
        query = (query or "").strip()[:200]
        if query:
            # The literal goes after the last argument, so TEXT comes last.
            conn.literal = query.encode("utf-8")
            typ, data = conn.uid("SEARCH", "CHARSET", "UTF-8", *keys, "TEXT")
        else:
            typ, data = conn.uid("SEARCH", None, *(keys or ["ALL"]))
        if typ != "OK":
            raise MailboxError("The support mailbox couldn't search that.")
        uids = sorted((int(u) for u in (data[0] or b"").split() if u.isdigit()), reverse=True)
        if show == "files" and uids:
            shapes = _fetch(conn, ",".join(map(str, uids)), "(UID BODYSTRUCTURE)")
            uids = [u for u in uids if _has_attachment((shapes.get(u) or {}).get("BODYSTRUCTURE"))]
        total = len(uids)
        chunk = uids[(page - 1) * PAGE_SIZE: page * PAGE_SIZE]
        fetched = _fetch(conn, ",".join(map(str, chunk)), _LIST_ITEMS) if chunk else {}
        unread = _unseen(conn, "INBOX") if folder == "inbox" else None
    messages = [_summary(uid, fetched[uid], folder) for uid in chunk if uid in fetched]
    return {
        "folder": folder,
        "address": address(),
        "page": page,
        "page_size": PAGE_SIZE,
        "total": total,
        "has_more": page * PAGE_SIZE < total,
        "show": show,
        "unread": unread,
        "messages": messages,
    }


def _unseen(conn: imaplib.IMAP4_SSL, name: str) -> Optional[int]:
    typ, data = conn.status(_quote(name), "(UNSEEN)")
    m = re.search(rb"UNSEEN (\d+)", data[0] or b"") if typ == "OK" and data else None
    return int(m.group(1)) if m else None


_unread_cache: tuple[float, Optional[int]] = (0.0, None)


def unread_count() -> Optional[int]:
    """Unread mails in the Inbox, kept 20 seconds: every open panel asks
    once a minute."""
    global _unread_cache
    at, value = _unread_cache
    if value is not None and time.monotonic() - at < 20:
        return value
    with _connect() as conn:
        value = _unseen(conn, "INBOX")
    _unread_cache = (time.monotonic(), value)
    return value


def forget_unread() -> None:
    global _unread_cache
    _unread_cache = (0.0, None)
    _counts_cache.clear()


_counts_cache: dict[str, tuple[float, dict]] = {}


def folder_counts() -> dict:
    """Mails and unread mails per folder, for the folder column. Kept 20
    seconds. A folder that doesn't exist yet (System before its first copy)
    counts as None."""
    hit = _counts_cache.get("all")
    if hit and time.monotonic() - hit[0] < 20:
        return hit[1]
    counts: dict[str, Optional[dict]] = {}
    with _connect() as conn:
        for key in FOLDERS:
            typ, data = conn.status(_quote(_folder(conn, key)), "(MESSAGES UNSEEN)")
            line = data[0] if typ == "OK" and data and isinstance(data[0], bytes) else b""
            total = re.search(rb"MESSAGES (\d+)", line)
            unseen = re.search(rb"UNSEEN (\d+)", line)
            counts[key] = {"total": int(total.group(1)), "unread": int(unseen.group(1)) if unseen else 0} if total else None
    _counts_cache["all"] = (time.monotonic(), counts)
    return counts


def _raw_message(conn: imaplib.IMAP4_SSL, uid: str) -> tuple[bytes, list[bytes]]:
    fetched = _fetch(conn, uid, "(UID FLAGS RFC822.SIZE)")
    fields = fetched.get(int(uid))
    if not fields:
        raise NotFound("This mail isn't there any more. It may have been moved or deleted.")
    size = fields.get("RFC822.SIZE")
    if isinstance(size, bytes) and size.isdigit() and int(size) > _MAX_MESSAGE_BYTES:
        raise MailboxError("This mail is too big to open here. Open it in Hostinger webmail.")
    body = _fetch(conn, uid, "(UID BODY.PEEK[])").get(int(uid), {}).get("BODY")
    if not isinstance(body, bytes):
        raise NotFound("This mail isn't there any more. It may have been moved or deleted.")
    flags = [f.lower() for f in (fields.get("FLAGS") or []) if isinstance(f, bytes)]
    return body, flags


def _parts(msg: Message) -> list[tuple[int, Message]]:
    return [(i, p) for i, p in enumerate(msg.walk()) if not p.is_multipart()]


def _is_attachment(part: Message) -> bool:
    disposition = part.get_content_disposition()
    if disposition == "attachment":
        return True
    # A named part that isn't shown inside the text (no Content-ID) is a file.
    return disposition is None and bool(part.get_filename()) and not part.get("Content-ID") \
        and not part.get_content_type().startswith("text/")


_DANGEROUS = re.compile(
    r"<(script|iframe|object|embed|frameset|frame|applet)\b.*?(</\1\s*>|$)"
    r"|<(meta|base|link)\b[^>]*>",
    re.I | re.S,
)
_REMOTE = re.compile(r"""(src|background)\s*=\s*["']?\s*(https?:)?//|url\(\s*["']?\s*(https?:)?//""", re.I)


def _clean_html(value: str, inline: dict[str, str]) -> str:
    """Belt and braces: the panel also shows mail HTML in a sandboxed frame
    with no scripts and no outside requests until "Show images"."""
    value = _DANGEROUS.sub("", value)
    if inline:
        def swap(m: re.Match) -> str:
            return inline.get(m.group(1).strip().lower(), m.group(0))
        value = re.sub(r"cid:([^\"'\s)>]+)", swap, value, flags=re.I)
    return value


def read_message(folder: str, uid: str, *, mark_read: bool = True) -> dict:
    uid = _check_uid(uid)
    with _connect() as conn:
        _select(conn, folder, write=mark_read)
        raw, flags = _raw_message(conn, uid)
        if mark_read and b"\\seen" not in flags:
            conn.uid("STORE", uid, "+FLAGS", "(\\Seen)")
            forget_unread()
    msg = BytesParser(policy=policy.default).parsebytes(raw)

    html_body = text_body = None
    try:
        part = msg.get_body(preferencelist=("html",))
        html_body = _part_text(part) if part is not None else None
        part = msg.get_body(preferencelist=("plain",))
        text_body = _part_text(part) if part is not None else None
    except Exception:
        logger.info("support mailbox: unreadable body in %s/%s", folder, uid)

    inline: dict[str, str] = {}
    inline_total = 0
    attachments = []
    for index, part in _parts(msg):
        if _is_attachment(part):
            payload = part.get_payload(decode=True) or b""
            attachments.append({
                "index": index,
                "filename": part.get_filename() or f"attachment-{index}",
                "content_type": part.get_content_type(),
                "size": len(payload),
            })
            continue
        cid = (part.get("Content-ID") or "").strip().strip("<>").lower()
        if cid and part.get_content_maintype() == "image" and html_body:
            payload = part.get_payload(decode=True) or b""
            if len(payload) <= _MAX_INLINE_IMAGE and inline_total + len(payload) <= _MAX_INLINE_TOTAL:
                inline_total += len(payload)
                inline[cid] = f"data:{part.get_content_type()};base64,{base64.b64encode(payload).decode()}"

    if html_body:
        html_body = _clean_html(html_body, inline)
    if not text_body and html_body:
        text_body = html_to_text(html_body)

    own = address().lower()
    reply_to = _people(msg, "Reply-To") or _people(msg, "From")
    reply_set = {p["email"].lower() for p in reply_to}
    reply_all_cc = [
        p for p in _people(msg, "To", "Cc")
        if p["email"].lower() not in reply_set and p["email"].lower() != own
    ]
    sender = _people(msg, "From")
    return {
        "uid": int(uid),
        "folder": folder,
        "from": sender[0] if sender else None,
        "to": _people(msg, "To"),
        "cc": _people(msg, "Cc"),
        "reply_to": reply_to,
        "reply_all_cc": reply_all_cc,
        "subject": _header(msg, "Subject"),
        "date": _date(msg),
        "message_id": _header(msg, "Message-ID"),
        "references": _header(msg, "References"),
        "html": html_body,
        "text": text_body or "",
        "has_remote_images": bool(html_body and _REMOTE.search(html_body)),
        "attachments": attachments,
        "unread": False if mark_read else b"\\seen" not in flags,
        "answered": b"\\answered" in flags,
    }


def attachment(folder: str, uid: str, index: int) -> tuple[bytes, str, str]:
    """(bytes, content type, filename) of one attachment."""
    uid = _check_uid(uid)
    with _connect() as conn:
        _select(conn, folder)
        raw, _ = _raw_message(conn, uid)
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    for i, part in _parts(msg):
        if i == index and _is_attachment(part):
            return (
                part.get_payload(decode=True) or b"",
                part.get_content_type(),
                part.get_filename() or f"attachment-{index}",
            )
    raise NotFound("That attachment isn't in this mail.")


# ── Public: move ───────────────────────────────────────────────────────────

def move(folder: str, uid: str, to: str) -> None:
    """Delete (to Trash), Not spam (Junk to Inbox) or back from Trash to the Inbox."""
    if (folder, to) not in MOVES:
        raise MailboxError("That move isn't allowed.")
    uid = _check_uid(uid)
    with _connect() as conn:
        _select(conn, folder, write=True)
        if not _fetch(conn, uid, "(UID)"):
            raise NotFound("This mail isn't there any more. It may have been moved or deleted.")
        target = _quote(_folder(conn, to))
        typ, _ = conn.uid("MOVE", uid, target)
        if typ != "OK":
            # Servers without MOVE: copy, then delete the original.
            typ, _ = conn.uid("COPY", uid, target)
            if typ != "OK":
                raise MailboxError("The support mailbox refused to move the mail.")
            conn.uid("STORE", uid, "+FLAGS", "(\\Deleted)")
            conn.expunge()
    forget_unread()


# ── Public: send ───────────────────────────────────────────────────────────

def _quoted_original(original: dict) -> tuple[str, str]:
    """The earlier mail under a reply, as (plain, html)."""
    who = original.get("from") or {}
    name = who.get("name") or who.get("email") or "someone"
    when = ""
    if original.get("date"):
        try:
            when = datetime.fromisoformat(original["date"]).strftime("%a, %d %b %Y at %H:%M UTC")
        except ValueError:
            when = ""
    intro = f"On {when}, {name} wrote:" if when else f"{name} wrote:"
    text = (original.get("text") or "").strip()[:_QUOTE_LIMIT]
    plain = intro + "\n" + "\n".join("> " + line for line in text.splitlines())
    html = (
        f'<div style="color:#64748b;margin-top:18px">{html_lib.escape(intro)}</div>'
        '<blockquote style="margin:6px 0 0;padding-left:12px;border-left:3px solid #cbd5e1;'
        f'color:#475569;white-space:pre-wrap">{html_lib.escape(text)}</blockquote>'
    )
    return plain, html


def send(
    *,
    to: list[str],
    cc: list[str],
    subject: str,
    body: str,
    reply_folder: Optional[str] = None,
    reply_uid: Optional[str] = None,
) -> dict:
    """Send a mail from support@ and keep a copy in Sent. With reply_*, it is
    a reply: it carries the thread headers, quotes the earlier mail, and marks
    that one answered."""
    original = None
    if reply_folder and reply_uid:
        original = read_message(reply_folder, reply_uid, mark_read=False)

    own = address()
    msg = EmailMessage()
    msg["From"] = formataddr((settings.SUPPORT_MAIL_NAME, own))
    msg["To"] = ", ".join(to)
    if cc:
        msg["Cc"] = ", ".join(cc)
    msg["Subject"] = subject
    msg["Date"] = format_datetime(datetime.now(timezone.utc))
    msg["Message-ID"] = make_msgid(domain=own.split("@")[-1] or None)

    plain = body.rstrip()
    html = (
        '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.55;'
        f'color:#0f172a;white-space:pre-wrap">{html_lib.escape(plain)}</div>'
    )
    if original:
        mid = original.get("message_id") or ""
        if mid:
            msg["In-Reply-To"] = mid
            # The thread so far, plus the mail answered.
            msg["References"] = f"{original.get('references') or ''} {mid}".strip()
        quote_plain, quote_html = _quoted_original(original)
        plain = f"{plain}\n\n{quote_plain}"
        html = html + quote_html

    msg.set_content(plain)
    msg.add_alternative(f"<!doctype html><html><body>{html}</body></html>", subtype="html")

    recipients = list(dict.fromkeys(to + cc))
    try:
        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
            server.starttls(context=ssl.create_default_context())
            server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
            server.send_message(msg, from_addr=own, to_addrs=recipients)
    except smtplib.SMTPRecipientsRefused as e:
        raise MailboxError("The mail server refused these addresses: " + ", ".join(e.recipients)) from e
    except (smtplib.SMTPException, OSError) as e:
        logger.warning("support mailbox: send failed: %s", e)
        raise MailboxError("The mail couldn't be sent. Nothing went out. Try again in a moment.") from e

    # It has gone out; the rest only keeps the mailbox tidy.
    saved = True
    try:
        with _connect() as conn:
            raw = msg.as_bytes(policy=policy.SMTP)
            typ, _ = conn.append(
                _quote(_folder(conn, "sent")), "(\\Seen)", imaplib.Time2Internaldate(time.time()), raw,
            )
            saved = typ == "OK"
            if original:
                _select(conn, reply_folder, write=True)
                conn.uid("STORE", _check_uid(reply_uid), "+FLAGS", "(\\Answered)")
    except Exception as e:
        saved = False
        logger.warning("support mailbox: sent, but not saved to Sent: %s", e)
    _counts_cache.clear()
    return {"message_id": msg["Message-ID"], "saved_to_sent": saved, "recipients": recipients}


# ── Public: keep a copy of an automatic mail ───────────────────────────────

def save_system_copy(raw: bytes) -> None:
    """File a copy of a mail the app sent by itself in the System folder,
    marked read. Makes the folder the first time. Never raises: the mail has
    already gone out, and a missing copy must not look like a failed send."""
    if not configured():
        return
    try:
        with _connect() as conn:
            name = _quote(_folder(conn, "system"))
            when = imaplib.Time2Internaldate(time.time())
            raw = raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            typ, data = conn.append(name, "(\\Seen)", when, raw)
            if typ != "OK":
                conn.create(name)
                conn.subscribe(name)
                typ, data = conn.append(name, "(\\Seen)", when, raw)
            if typ != "OK":
                logger.warning("support mailbox: system copy refused: %s", data)
    except Exception as e:
        logger.warning("support mailbox: system copy not saved: %s", e)
