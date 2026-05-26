# OpenSOP — Install Guide for AI Agents

<!-- ASCII_BANNER -->
```
  ╔═════════════════════════════════╗
  ║  OpenSOP                        ║
  ║  Processes as APIs              ║
  ╚═════════════════════════════════╝

  [ form ] ──▶ [ decision ] ──▶ [ done ]
```
<!-- ASCII_BANNER_END -->

---

You are an AI agent (Claude Code, Cursor, Codex, or similar) installing
OpenSOP for a human operator. This document is a **CONTRACT**. Your job is to:

- Execute every numbered step in order
- Pause at each **DECISION GATE** and ask the operator the listed question(s) before continuing
- Verify each step completes before moving on
- Use the recovery paths when something fails
- Never continue blindly past a failed verification

---

## Invariants you must preserve

1. **Never silently choose a default at a decision gate.** Each gate says
   exactly what to ask. Ask it word-for-word or adapt naturally, but do not
   skip it or answer it yourself.

2. **Never skip a verification step.** If a verification fails, stop and use
   the recovery path for that step. Do not move to the next step.

3. **Never log or echo the operator's secrets.** `RAILS_MASTER_KEY`,
   `SECRET_KEY_BASE`, `OPENSOP_API_TOKEN`, and `POSTGRES_PASSWORD` are written
   to `.env`. Do not print them to the terminal or include them in any summary
   you produce.

4. **Never destroy existing data without confirmation.** If the install
   directory or any Docker volume already exists, stop and ask the operator
   before touching it.

5. **The `.env` file is the source of truth.** Every secret and configuration
   choice flows from it into the container via `docker compose`. Do not patch
   `docker-compose.yml` directly.

---

## Prerequisites — check before any decision gate

Run these checks. If any fails, stop and use the recovery path listed.

### P1 — Docker

```bash
docker --version
docker compose version
```

- Both commands must succeed.
- Docker Compose plugin must be v2.0 or later (`docker compose`, not
  `docker-compose`).
- **Recovery:** If Docker is not installed, tell the operator to visit
  <https://docs.docker.com/get-docker/> and re-run this install after Docker
  Desktop (or Engine + Compose plugin) is installed. Stop here.

### P2 — Git

```bash
git --version
```

- **Recovery:** If Git is not installed, point the operator to
  <https://git-scm.com/downloads>. Stop.

### P3 — Port availability

```bash
# Check if port 3000 is in use
lsof -i :3000 2>/dev/null | grep LISTEN || echo "port 3000 is free"
```

- If port 3000 is in use, note it — the operator will be asked about this at
  Decision Gate 2.

### P4 — Existing install directory

Check whether `~/opensop` (or any path the operator may later name) already
exists. If it does, note it — you will ask about it at Decision Gate 1.

---

## DECISION GATE 1 — Install location

Ask the operator:

> "Where should I clone OpenSOP? The default is `~/opensop`. You can give me
> any absolute path. If a directory already exists there I will ask before
> touching it."

Record the answer as `INSTALL_DIR`. If the directory already exists:

> "That directory already exists. Should I (a) abort so you can inspect it,
> (b) install into a subdirectory inside it, or (c) delete it and start fresh?
> I will not delete it without your explicit confirmation of option (c)."

Do not proceed until the operator has confirmed a path and any conflict
is resolved.

---

## DECISION GATE 2 — Mode

OpenSOP has three operating modes with different security implications.
Ask the operator:

> "Which mode do you want to run?
>
> 1. **local-dev** — binds to localhost only, developer defaults, single user,
>    no email, no LLM required. Best for trying it out.
>
> 2. **self-host-local** — binds to localhost, production settings, single
>    team on this machine. Requires a real master key and API token.
>
> 3. **self-host-public** — binds to a real domain (e.g. `opensop.acme.com`),
>    behind a reverse proxy or TLS terminator. Requires a real master key,
>    API token, and domain configuration.
>
> Which mode? (1/2/3 or local-dev/self-host-local/self-host-public)"

Record the answer as `MODE`.

If port 3000 was found to be in use (P3 above), ask now:

> "Port 3000 is already in use. Which port should OpenSOP bind to on your
> host? (e.g. 3001, 8080)"

Record as `OPENSOP_PORT` (default `3000`).

---

## DECISION GATE 3 — Domain (self-host-public only)

*Skip this gate entirely if MODE is `local-dev` or `self-host-local`.*

Ask the operator:

> "What domain will OpenSOP be served on? (e.g. `opensop.acme.com`)
> This is the domain your reverse proxy or TLS terminator points at the
> container."

Record as `DOMAIN`. Derive:

- `OPENSOP_BASE_URL` = `https://<DOMAIN>`
- `OPENSOP_RP_ID` = `<DOMAIN>` (WebAuthn relying-party ID must be the apex
  domain or a registrable suffix of it)
- `OPENSOP_ORIGIN` = `https://<DOMAIN>`
- `RAILS_ALLOWED_HOSTS` = `<DOMAIN>`

Confirm with the operator:

> "I will configure:
>   OPENSOP_BASE_URL=https://<DOMAIN>
>   OPENSOP_RP_ID=<DOMAIN>
>   OPENSOP_ORIGIN=https://<DOMAIN>
>   RAILS_ALLOWED_HOSTS=<DOMAIN>
> Is that correct?"

---

## DECISION GATE 4 — Authentication

OpenSOP supports two sign-in paths. Ask the operator:

> "How should users sign in?
>
> 1. **Passkeys only** (WebAuthn) — works entirely without external services.
>    Users register and sign in with a hardware key, Face ID, Touch ID, or
>    Windows Hello. Recommended default.
>
> 2. **Passkeys + magic links** — adds email-based sign-in. Requires a Resend
>    account and API key (<https://resend.com>). Choose this if your users
>    don't have passkey-capable devices or you want an email fallback.
>
> Which? (1/2)"

If the operator chooses option 2, ask:

> "Please provide:
>   - Your Resend API key (starts with `re_`)
>   - The From address for outgoing mail (e.g. `OpenSOP <noreply@acme.com>`)"

Record as `RESEND_API_KEY` and `OPENSOP_MAILER_FROM`.

---

## DECISION GATE 5 — LLM provider

OpenSOP's `judgment` step type delegates decisions to an LLM. Ask the
operator:

> "Do your processes use `judgment` steps? If not, you can skip LLM
> configuration — judgment steps will pause as 'escalated' and wait for
> a human to submit a decision via the API.
>
> If yes, which provider?
>
> 1. **None** — judgment steps escalate to humans (no API key needed)
> 2. **Anthropic** — requires an Anthropic API key
>
> (OpenAI is not currently supported.)
>
> Which? (1/2)"

If the operator chooses Anthropic, ask:

> "Please provide your Anthropic API key (starts with `sk-ant-`)."

Record as `ANTHROPIC_API_KEY`.

---

## DECISION GATE 6 — First admin email

Ask the operator:

> "What email address should the first admin account use? This creates the
> bootstrap admin on first boot. After the first user exists, this setting
> is ignored."

Record as `OPENSOP_BOOTSTRAP_EMAIL`.

Validate that it looks like an email (contains `@`). If not, ask again.

---

## DECISION GATE 7 — Confirm before proceeding

Print a summary of every choice the operator made, **without showing the
values of any secret** (mask them as `[set]` or `[not set]`):

```
Install location:      <INSTALL_DIR>
Mode:                  <MODE>
Port:                  <OPENSOP_PORT>
Domain:                <DOMAIN or "localhost (local mode)">
Base URL:              <OPENSOP_BASE_URL>
Authentication:        <"passkeys only" or "passkeys + magic links">
LLM provider:          <"none" or "anthropic">
First admin email:     <OPENSOP_BOOTSTRAP_EMAIL>
RAILS_MASTER_KEY:      [will be generated]
SECRET_KEY_BASE:       [will be generated]
OPENSOP_API_TOKEN:     [will be generated]
POSTGRES_PASSWORD:     [will be generated]
RESEND_API_KEY:        [set / not set]
ANTHROPIC_API_KEY:     [set / not set]
```

Ask:

> "Does this look right? I'll proceed to clone and configure once you confirm.
> (yes/no)"

Do not continue until the operator confirms.

---

## Step 1 — Clone the repository

```bash
git clone https://github.com/Chosen9115/opensop.git <INSTALL_DIR>
cd <INSTALL_DIR>
```

**Verification:** confirm `<INSTALL_DIR>` exists and contains a `docker-compose.yml`.

```bash
test -f <INSTALL_DIR>/docker-compose.yml && echo "OK" || echo "MISSING"
```

If `MISSING`: show the clone output and stop. The clone may have failed.

---

## Step 2 — Generate secrets

Generate four secrets. Do not echo them to the terminal; write them directly
to `.env` in Step 3.

```bash
# Run each command and capture the output quietly
RAILS_MASTER_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 64)
OPENSOP_API_TOKEN=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)
```

**Invariant:** if `openssl` is not available, abort and tell the operator:
`openssl` is required for secret generation. On macOS it is bundled; on
Linux install with `apt install openssl` or `yum install openssl`.

---

## Step 3 — Write .env

Write the following to `<INSTALL_DIR>/.env`. Fill in every value from the
operator's answers and the generated secrets. Do not leave any required field
blank.

```bash
# OpenSOP environment — generated by install agent
# Do not commit this file.

RAILS_MASTER_KEY=<generated>
SECRET_KEY_BASE=<generated>
OPENSOP_API_TOKEN=<generated>
POSTGRES_USER=opensop
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=opensop_production
OPENSOP_PORT=<OPENSOP_PORT>
RAILS_ENV=production
RAILS_LOG_LEVEL=info
RAILS_ALLOWED_HOSTS=<RAILS_ALLOWED_HOSTS>
OPENSOP_BASE_URL=<OPENSOP_BASE_URL>
OPENSOP_RP_ID=<OPENSOP_RP_ID>
OPENSOP_ORIGIN=<OPENSOP_ORIGIN>
OPENSOP_RP_NAME=OpenSOP
OPENSOP_BOOTSTRAP_EMAIL=<OPENSOP_BOOTSTRAP_EMAIL>
SOLID_QUEUE_IN_PUMA=true
```

Append these only if set:

```bash
# Only if magic links enabled:
RESEND_API_KEY=<RESEND_API_KEY>
OPENSOP_MAILER_FROM=<OPENSOP_MAILER_FROM>
OPENSOP_MAILER_MODE=send

# Only if Anthropic LLM enabled:
ANTHROPIC_API_KEY=<ANTHROPIC_API_KEY>
```

**For local-dev mode**, use these values instead:

```
RAILS_ENV=development
RAILS_ALLOWED_HOSTS=localhost,127.0.0.1
OPENSOP_BASE_URL=http://localhost:<OPENSOP_PORT>
OPENSOP_RP_ID=localhost
OPENSOP_ORIGIN=http://localhost:<OPENSOP_PORT>
# local-dev runs Rails in development, which uses the async queue adapter and
# never migrates the Solid Queue tables. The Solid Queue supervisor must stay
# OFF inside Puma here, or it crashes the app on boot.
SOLID_QUEUE_IN_PUMA=false
```

**Verification:** confirm the file was written and is non-empty.

```bash
test -s <INSTALL_DIR>/.env && echo "OK" || echo "MISSING"
```

Verify no required field is blank (check at minimum these four):

```bash
grep -E "^RAILS_MASTER_KEY=.+" <INSTALL_DIR>/.env && \
grep -E "^SECRET_KEY_BASE=.+" <INSTALL_DIR>/.env && \
grep -E "^OPENSOP_API_TOKEN=.+" <INSTALL_DIR>/.env && \
grep -E "^POSTGRES_PASSWORD=.+" <INSTALL_DIR>/.env && \
echo "All required secrets set" || echo "MISSING REQUIRED SECRET"
```

---

## Step 4 — Remove config/credentials.yml.enc

**Why this step exists:** the `config/credentials.yml.enc` committed to the
repository was encrypted with the original author's master key. A fresh install
using a newly generated `RAILS_MASTER_KEY` cannot decrypt it, and if the file is
present Rails aborts on first boot with
`ActiveSupport::MessageEncryptor::InvalidMessage`.

OpenSOP does not read Rails credentials at runtime — `SECRET_KEY_BASE` and every
other secret come from environment variables (the `.env` you wrote in Step 3).
So the encrypted file is not needed: delete it.

```bash
cd <INSTALL_DIR>
rm -f config/credentials.yml.enc
```

**Verification:** confirm it is gone (Rails runs fine without it):

```bash
test ! -e config/credentials.yml.enc && echo "OK" || echo "STILL PRESENT"
```

---

## Step 5 — Bring services up

```bash
cd <INSTALL_DIR>
docker compose up -d
```

Watch for compose's `:?` required-variable errors. If compose exits immediately
with an error like:

```
variable "RAILS_MASTER_KEY" is not set. Defaulting to a blank string.
```

or

```
service "app" didn't build successfully
```

Stop here. Use the recovery path in the **Recovery paths** section below.

**Verification:** confirm both services started:

```bash
docker compose ps
```

Both `db` and `app` should show `running` or `Up`.

---

## Step 6 — Wait for health checks

Poll the app health endpoint. Wait up to 120 seconds for the app to become
healthy (Rails boots, runs migrations, starts Puma):

```bash
for i in $(seq 1 24); do
  STATUS=$(curl -fsS "http://localhost:<OPENSOP_PORT>/up" -o /dev/null -w "%{http_code}" 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    echo "App healthy"
    break
  fi
  echo "Waiting... ($i/24) — status: ${STATUS:-no response}"
  sleep 5
done
```

**Verification:** the loop must print "App healthy". If it does not after 24
attempts (~120 seconds), stop and use the recovery path below.

---

## Step 7 — Smoke test

Retrieve the API token from `.env` and call the discovery endpoint:

```bash
TOKEN=$(grep '^OPENSOP_API_TOKEN=' <INSTALL_DIR>/.env | cut -d= -f2)
curl -fsS \
  -H "X-SOP-Token: $TOKEN" \
  "http://localhost:<OPENSOP_PORT>/sop/" \
  | head -c 500
```

**Verification:** the response must be HTTP 200 and contain JSON. It should
look like:

```json
{"processes": [...], "total": 0}
```

(Zero processes is correct on a fresh install before any `.sop.yaml` files
are loaded.)

**Recovery:**
- HTTP 401: the `X-SOP-Token` header value is wrong. Re-read the token from
  `.env` and retry.
- HTTP 503 / `server_misconfigured`: `OPENSOP_API_TOKEN` is empty inside the
  running container. Diagnose and restart:
  ```bash
  docker compose exec app printenv OPENSOP_API_TOKEN
  # If blank:
  docker compose down && docker compose up -d
  ```

---

## Step 8 — Print success and first-login instructions

First boot creates the admin account from `OPENSOP_BOOTSTRAP_EMAIL` and prints a
one-time **first-login URL** to the logs (also written to
`tmp/opensop_first_login.txt`). That URL — not the plain sign-in page — is how the
first admin registers their passkey: the sign-in page rejects them until a passkey
exists. Fetch it:

```bash
docker compose logs app 2>/dev/null | grep "First-login URL" | tail -1
```

Print a message to the operator (do not include any secret values):

```
OpenSOP is running.

Web UI:   http://localhost:<OPENSOP_PORT>   (or https://<DOMAIN> if self-host-public)
API base: http://localhost:<OPENSOP_PORT>/sop/
API auth: X-SOP-Token header — value is in <INSTALL_DIR>/.env (OPENSOP_API_TOKEN)

First login:
  1. Open the first-login URL above in your browser (valid 7 days).
     The plain sign-in page will reject you until a passkey is registered —
     use this URL for the very first sign-in.
  2. Register a passkey when prompted (hardware key, Face ID, Touch ID, Windows Hello).
  3. After that, sign in normally at the web UI as <OPENSOP_BOOTSTRAP_EMAIL>.
```

If magic links were enabled (RESEND_API_KEY set), the operator can instead request
a sign-in link from the sign-in page. For local-dev or a trusted single-machine
self-host, login can be skipped entirely with `OPENSOP_DISABLE_AUTH=true` in `.env`
(ignored on public deployments — see `.env.example`).

```
Stack management:
  Logs:    docker compose -f <INSTALL_DIR>/docker-compose.yml logs -f app
  Stop:    docker compose -f <INSTALL_DIR>/docker-compose.yml down
  Restart: docker compose -f <INSTALL_DIR>/docker-compose.yml restart app

Next steps:
  - Drop a .sop.yaml file into <INSTALL_DIR>/processes/ and restart the app
    to register your first process.
  - Read the API docs: <INSTALL_DIR>/docs/API.md
  - See INSTALL.md for a human-readable reference of every configuration option.
```

---

## Recovery paths

### Docker not installed

Tell the operator: Docker is required. Visit <https://docs.docker.com/get-docker/>
and install Docker Desktop (macOS/Windows) or the Docker Engine + Compose
plugin (Linux). Then re-run this install. **Stop here.**

### Port already in use

Return to Decision Gate 2 and ask the operator for an alternate port. Update
`OPENSOP_PORT` in `.env`. Then return to Step 5.

### compose `:?` required-variable error on `up`

A required env var is missing or blank. Run:

```bash
grep -E "^(RAILS_MASTER_KEY|SECRET_KEY_BASE|OPENSOP_API_TOKEN|POSTGRES_PASSWORD)=" \
  <INSTALL_DIR>/.env
```

Any line showing `KEY=` with no value after the `=` is the culprit. Fill it
in, then re-run `docker compose up -d`.

### Database does not become healthy

```bash
docker compose logs db | tail -50
```

Show the output to the operator. Common causes: volume permission issue,
`POSTGRES_PASSWORD` blank, or a pre-existing data volume from a different
PostgreSQL version. If the volume is stale:

> "The database volume may be incompatible. Shall I delete it and start fresh?
> This will destroy all existing data in the volume `opensop-pgdata`. (yes/no)"

Only delete if the operator confirms:

```bash
docker compose down -v   # removes volumes — data loss, operator confirmed
docker compose up -d
```

### App does not become healthy (Step 6 times out)

```bash
docker compose logs app | tail -100
```

Show the output. Common causes:

- **`ActiveSupport::MessageEncryptor::InvalidMessage`** — the committed
  `config/credentials.yml.enc` is still present and can't be decrypted with this
  install's key. Delete it (Step 4): `rm -f config/credentials.yml.enc`, then
  `docker compose restart app`. OpenSOP reads its secrets from env, not credentials.
- **Missing required env var** — compose `:?` syntax logs a clear error.
  Fill in the missing var in `.env`, then `docker compose restart app`.
- **OOM / memory error** — the container ran out of memory. The minimum is
  512 MB. Check `docker stats` and increase container memory limits if needed.

### Smoke test returns 401

The API token in the request does not match `OPENSOP_API_TOKEN` in the
running container. Check:

```bash
docker compose exec app printenv OPENSOP_API_TOKEN
grep '^OPENSOP_API_TOKEN=' <INSTALL_DIR>/.env
```

If they differ, the container is using a stale value. Run:

```bash
docker compose down && docker compose up -d
```

### Smoke test returns 503 server_misconfigured

`OPENSOP_API_TOKEN` is blank inside the container:

```bash
docker compose exec app printenv OPENSOP_API_TOKEN
```

If blank, `OPENSOP_API_TOKEN` is missing from `.env`. Fill it in, then:

```bash
docker compose down && docker compose up -d
```

---

## What "done" looks like

After Step 8, the operator should have:

- OpenSOP accessible at `http://localhost:<PORT>` (or `https://<DOMAIN>` for
  self-host-public)
- A working admin account reachable via the bootstrap email
- A live `/sop/` API authenticated by the token in `.env`
- A Docker Compose stack manageable with `docker compose logs`, `down`,
  `restart`

---

## Next steps for the operator

Once the install is verified:

1. **Author your first process.** Drop a `.sop.yaml` file into the `processes/`
   directory. See `docs/API.md` and the examples in `processes/examples/` for
   the format. Restart the app to load it:
   ```bash
   docker compose restart app
   curl -H "X-SOP-Token: $TOKEN" http://localhost:<PORT>/sop/
   ```

2. **Read the human-friendly install guide** for configuration options not
   covered here: `INSTALL.md` in the repo root.

3. **Explore the API.** Every process is immediately a REST API:
   ```bash
   # Start an instance
   curl -X POST -H "X-SOP-Token: $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"company_name": "Acme"}' \
        http://localhost:<PORT>/sop/customer-onboarding/start
   ```

4. **Set up TLS** (self-host-public). See `docker-compose.override.yml.example`
   for a Caddy/Traefik overlay pattern.
