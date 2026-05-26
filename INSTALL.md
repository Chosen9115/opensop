# OpenSOP — Self-Host Install Guide

This guide covers a Docker Compose install of OpenSOP on any Linux or macOS
machine. It takes about 10 minutes.

> **AI agent install:** tell your agent to read and follow
> `INSTALL_FOR_AGENTS.md` — it contains a richer, machine-readable version
> of this guide with decision gates, verification steps, and recovery paths.

---

## Prerequisites

| Requirement | Minimum version | Check |
|---|---|---|
| Docker | 24.0 | `docker --version` |
| Docker Compose plugin | 2.0 | `docker compose version` |
| Git | any | `git --version` |
| `openssl` | any | `openssl version` |

At least **512 MB of RAM** must be available to the Docker VM. Rails will OOM
on 256 MB.

---

## 1. Clone

```bash
git clone https://github.com/Chosen9115/opensop.git ~/opensop
cd ~/opensop
```

---

## 2. Generate secrets

```bash
echo "RAILS_MASTER_KEY=$(openssl rand -hex 32)"
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
echo "OPENSOP_API_TOKEN=$(openssl rand -hex 32)"
echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
```

Copy these values — you will paste them into `.env` in the next step.

---

## 3. Create .env

```bash
cp .env.example .env
```

Open `.env` in your editor and fill in all required values. At minimum:

```
RAILS_MASTER_KEY=    ← from step 2
SECRET_KEY_BASE=     ← from step 2
OPENSOP_API_TOKEN=   ← from step 2
POSTGRES_PASSWORD=   ← from step 2
OPENSOP_BOOTSTRAP_EMAIL=  ← your admin email address
```

See `.env.example` for a full annotated reference of every option.

### Mode-specific settings

**local-dev** (localhost, developer defaults):

```bash
RAILS_ENV=development
OPENSOP_BASE_URL=http://localhost:3000
OPENSOP_RP_ID=localhost
OPENSOP_ORIGIN=http://localhost:3000
RAILS_ALLOWED_HOSTS=localhost,127.0.0.1
# development uses the async queue adapter and has no Solid Queue tables, so the
# in-Puma supervisor must be off or it crashes the app on boot.
SOLID_QUEUE_IN_PUMA=false
```

**self-host-local** (production settings, localhost only):

No changes from `.env.example` defaults. Just fill in the required secrets.

**self-host-public** (real domain, behind a reverse proxy):

```bash
OPENSOP_BASE_URL=https://opensop.acme.com
OPENSOP_RP_ID=opensop.acme.com
OPENSOP_ORIGIN=https://opensop.acme.com
RAILS_ALLOWED_HOSTS=opensop.acme.com
```

Copy `docker-compose.override.yml.example` to `docker-compose.override.yml`
and edit it for your proxy setup.

---

## 4. Remove the committed credentials file

The committed `config/credentials.yml.enc` was encrypted with the author's
master key, so a fresh install's `RAILS_MASTER_KEY` can't decrypt it — and if
it's present, Rails aborts on boot with
`ActiveSupport::MessageEncryptor::InvalidMessage`.

OpenSOP reads its secrets from environment variables (`SECRET_KEY_BASE` and the
rest come from `.env`), not from Rails credentials, so the file isn't needed.
Just delete it:

```bash
rm -f config/credentials.yml.enc
```

Verify it's gone (the app runs fine without it):

```bash
test ! -e config/credentials.yml.enc && echo "OK"
```

---

## 5. Start

```bash
docker compose up -d
```

Docker Compose will build the image, start PostgreSQL, run `db:prepare`
(create + migrate), and start the Rails app via Puma + Thruster.

Watch progress:

```bash
docker compose logs -f app
```

---

## 6. Verify

Wait for the health check (up to ~90 seconds on first boot):

```bash
curl http://localhost:3000/up
# → HTTP 200
```

Then smoke-test the API:

```bash
TOKEN=$(grep '^OPENSOP_API_TOKEN=' .env | cut -d= -f2)
curl -H "X-SOP-Token: $TOKEN" http://localhost:3000/sop/
# → {"processes": [], "total": 0}
```

---

## 7. First login

First boot creates the admin from `OPENSOP_BOOTSTRAP_EMAIL` and prints a one-time
**first-login URL** to the logs (also saved to `tmp/opensop_first_login.txt`).
The plain sign-in page rejects you until a passkey is registered, so use this URL
for the very first sign-in. Fetch it:

```bash
docker compose logs app | grep "First-login URL"
```

1. Open that first-login URL in a browser (valid 7 days).
2. Register a passkey when prompted. A hardware key, Face ID, Touch ID, or
   Windows Hello all work.
3. From then on, sign in normally at `http://localhost:3000` (or your domain)
   as `OPENSOP_BOOTSTRAP_EMAIL`.

If you enabled magic-link email sign-in (`RESEND_API_KEY` set), you can instead
request a link from the sign-in page. For local-dev or a trusted single-machine
self-host, you can skip login entirely with `OPENSOP_DISABLE_AUTH=true` in `.env`
(ignored on public deployments — see `.env.example`).

---

## Configuration reference

| Variable | Required | Description |
|---|---|---|
| `RAILS_MASTER_KEY` | Yes | Encrypts Rails secrets. Generate: `openssl rand -hex 32` |
| `SECRET_KEY_BASE` | Yes | Signs cookies. Generate: `openssl rand -hex 64` |
| `OPENSOP_API_TOKEN` | Yes | Bearer token for `X-SOP-Token` auth. Generate: `openssl rand -hex 32` |
| `POSTGRES_PASSWORD` | Yes | PostgreSQL password (internal) |
| `OPENSOP_BOOTSTRAP_EMAIL` | Recommended | Creates first admin on boot |
| `OPENSOP_BASE_URL` | Yes (public) | Full URL, e.g. `https://opensop.acme.com` |
| `OPENSOP_RP_ID` | Yes (public) | WebAuthn relying-party ID (apex domain) |
| `OPENSOP_ORIGIN` | Yes (public) | WebAuthn origin (same as `OPENSOP_BASE_URL`) |
| `RAILS_ALLOWED_HOSTS` | Yes (public) | Comma-separated allowed Host headers |
| `RESEND_API_KEY` | Optional | Enable magic-link email sign-in via Resend |
| `OPENSOP_MAILER_FROM` | Optional | From address for outgoing mail |
| `ANTHROPIC_API_KEY` | Optional | Enable LLM-backed `judgment` steps |
| `OPENSOP_PORT` | Optional | Host port (default `3000`) |
| `RAILS_LOG_LEVEL` | Optional | `debug` / `info` / `warn` (default `info`) |

---

## Stack management

```bash
# View logs
docker compose logs -f app

# Stop
docker compose down

# Stop and delete all data volumes (destructive)
docker compose down -v

# Restart app only
docker compose restart app

# Open a Rails console
docker compose exec app bin/rails console
```

---

## Troubleshooting

**`ActiveSupport::MessageEncryptor::InvalidMessage` on boot**
The committed `config/credentials.yml.enc` is still present and can't be decrypted
with your key. Delete it (Step 4): `rm -f config/credentials.yml.enc`, then
`docker compose down && docker compose up -d`.

**HTTP 401 from `/sop/`**
The `X-SOP-Token` header value doesn't match `OPENSOP_API_TOKEN`. Re-read
the token from `.env`.

**HTTP 503 `server_misconfigured`**
`OPENSOP_API_TOKEN` is blank in the running container. Verify it in `.env`,
then `docker compose down && docker compose up -d`.

**App does not start, exits immediately**
Run `docker compose logs app` — the `:?` syntax in `docker-compose.yml`
prints which required variable is missing.

**Database not healthy**
Run `docker compose logs db`. If the volume is stale from a different
PostgreSQL version, delete it (after backing up any data you need):
`docker compose down -v && docker compose up -d`.

**Port 3000 in use**
Set `OPENSOP_PORT=3001` (or any free port) in `.env` and re-run
`docker compose up -d`.

---

## Next steps

- **Add processes:** drop `.sop.yaml` files into `processes/` and restart.
- **API docs:** `docs/API.md`
- **Process authoring guide:** `docs/process-authoring.md`
- **TLS / reverse proxy:** see `docker-compose.override.yml.example`
- **AI agent install:** `INSTALL_FOR_AGENTS.md`
