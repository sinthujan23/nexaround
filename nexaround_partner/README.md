# nexARound Partner Portal

The vendor-facing half of the Experiences marketplace, at
**https://partner.nexaround.com**. A vendor signs in and manages their own
business profile, packages and enquiries — and can reach nothing belonging to
anyone else.

Built from the `nexaround_admin` template: React 19 + Vite, plain JSX, no
router (one page name in state), and `src/index.css` copied byte-for-byte so
the two panels stay one design system.

## Accounts

There is **no sign-up page**. An admin creates a login from the admin panel
(Experiences → a vendor → *Portal logins*), and the vendor sets their own
password from an emailed link. Nobody at NexAround ever sees the password.

- Invite links last 72 hours, reset links 1 hour, and both are single-use.
- Resending revokes the previous link.
- Disabling a login, or hiding the vendor, blocks access immediately — the
  latter also stops them reading their enquiry inbox.

## Develop

```bash
npm install
npm run dev        # talks to the live API at api.nexaround.com
npm run lint
```

## Deploy

`dist/` is bind-mounted into the container, so a build is the deploy — no
restart needed.

```bash
npm run build
```

First time only:

```bash
docker compose up -d      # nginx:alpine on 127.0.0.1:8021
```

### Why `nginx.conf` is mounted

Stock `nginx:alpine` has no `try_files`, so it 404s any path that is not a real
file. `/set-password` is not a real file, and it is the **first URL any vendor
ever opens** — the invite link. The mounted config serves `index.html` for
every path and lets the app route itself. The admin panel gets away without
this because it only ever has one URL.

## Host wiring (done once, recorded here)

- **DNS** `partner.nexaround.com` → this server.
- **nginx** a `partner.nexaround.com` block in
  `/etc/nginx/sites-available/nexaround`, proxying to `127.0.0.1:8021`,
  mirroring the `admin.nexaround.com` block.
- **TLS** `certbot --nginx -d partner.nexaround.com` — its own certificate,
  matching the convention of the other hosts, auto-renewing.
- **CORS** `partner.nexaround.com` must be in `BACKEND_CORS_ORIGINS` in
  `nexaround_backend/.env`.

  ⚠️ After changing that file, use **`docker compose up -d api`**, not
  `restart` — a restart does not re-read `.env`, and every request from the
  portal would then fail CORS with nothing logged server-side, which reads as
  "the portal is broken" rather than "the config did not reload".

## What a vendor cannot do

The profile page has no inputs for Active/Hidden, rating, review count,
internal notes or sort order — but that is only presentation. The server keeps
its own list of writable columns (`_PARTNER_VENDOR_SCALARS` in
`app/api/v1/partner.py`) and drops those fields even when a crafted request
carries them, because the admin update path is a full replacement where every
field has a default. `tests/test_partner_scalars.py` pins both halves.
