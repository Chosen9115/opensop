# Deploying the OpenSOP Public Demo to Fly.io

This runbook walks through standing up **`opensop-demo`** at `demo.opensop.ai`
using `fly.demo.toml`. It is a companion to `docs/deploy-fly.md` (primary
deployment). The demo app is intentionally minimal and cost-optimised.

> **Heads up:** every `flyctl` command that provisions infrastructure costs
> money. Read each command before you run it.

---

## What this app does differently

The demo deployment runs with `DEMO_MODE=true`, which activates:

- **Public demo banner** — a sitewide notice that data resets daily.
- **Rate limiting** — stricter per-IP limits to prevent abuse.
- **Daily reset** — a scheduled job truncates instances and step data at UTC midnight.
- **Public API token** — a well-known `OPENSOP_API_TOKEN` value so visitors
  can try the REST API without signing up.
- **Read-only process definitions** — the UI disallows editing or deleting
  built-in demo processes (creation still works in sandboxed form).
- **`/docs` route** — interactive API documentation enabled in the demo.

These features are gated on `ENV["DEMO_MODE"]` in the application code and
have no effect on the primary deployment.

---

## 0. Prerequisites

1. [`flyctl` installed](https://fly.io/docs/hands-on/install-flyctl/).
2. `fly auth login` (one-time).
3. `config/master.key` exists locally:

   ```sh
   ls config/master.key
   ```

   If it is missing, recover it from your password manager — you cannot
   decrypt production credentials without it.

4. A Fly organisation that can create apps and Postgres clusters.

---

## 1. Create the app

```sh
flyctl apps create opensop-demo
```

Do **not** run `fly launch` — we already have `fly.demo.toml`.

---

## 2. Create the Postgres cluster

```sh
flyctl postgres create \
  --name opensop-demo-db \
  --region ord \
  --initial-cluster-size 1 \
  --vm-size shared-cpu-1x \
  --volume-size 1
```

- 1 GB volume is enough for demo data that resets daily.
- Match `--region` to `primary_region` in `fly.demo.toml` (`ord`).
- **Save the connection string** Fly prints — you need it in step 4.

---

## 3. Attach Postgres to the app

```sh
flyctl postgres attach opensop-demo-db --app opensop-demo
```

This creates a `opensop_demo` role + database and sets `DATABASE_URL` as a
secret on the app automatically.

---

## 4. Create cache + queue databases

Open a psql session on the cluster:

```sh
flyctl postgres connect -a opensop-demo-db
```

Inside psql:

```sql
CREATE DATABASE opensop_demo_cache OWNER opensop_demo;
CREATE DATABASE opensop_demo_queue OWNER opensop_demo;
\q
```

Now set the two extra URL secrets. They reuse the same host and credentials
as `DATABASE_URL`; only the database name at the end changes. Fly attach URLs
look like:

```
postgres://opensop_demo:PASSWORD@opensop-demo-db.flycast:5432/opensop_demo
```

Replace the trailing `/opensop_demo` with the new database names:

```sh
flyctl secrets set \
  CACHE_DATABASE_URL="postgres://opensop_demo:PASSWORD@opensop-demo-db.flycast:5432/opensop_demo_cache" \
  QUEUE_DATABASE_URL="postgres://opensop_demo:PASSWORD@opensop-demo-db.flycast:5432/opensop_demo_queue" \
  --app opensop-demo
```

---

## 5. Set secrets

```sh
flyctl secrets set \
  RAILS_MASTER_KEY="$(cat config/master.key)" \
  OPENSOP_API_TOKEN="demo-public-token-resets-daily" \
  OPENSOP_BASE_URL="https://demo.opensop.ai" \
  --app opensop-demo
```

- `OPENSOP_API_TOKEN` is the public demo token. The same value powers
  `Sop::ApplicationController` auth (visitors send it as the `X-SOP-Token`
  header) AND the value displayed on the demo homepage — `Opensop::DemoMode.api_token`
  reads `OPENSOP_API_TOKEN` first. Setting one secret is enough.
- `OPENSOP_BASE_URL` is used by the runtime to build webhook callback URLs.
- `DEMO_API_TOKEN` is **not required**. It exists only as a fallback for local
  development and is only consulted when `OPENSOP_API_TOKEN` is unset. Don't
  bother setting it on Fly.

---

## 6. Deploy

```sh
flyctl deploy --config fly.demo.toml
```

What happens:

1. Fly builds the image from the repo's `Dockerfile` (same image as primary).
2. A release machine runs `./bin/rails db:prepare` — migrates all three
   databases (primary, cache, queue).
3. The web machine boots. Thruster listens on port 3000; Fly's proxy handles
   TLS and routes traffic to it.
4. Solid Queue starts inside Puma (`SOLID_QUEUE_IN_PUMA=true`).
5. With `min_machines_running = 0` the machine stops when idle and wakes on
   the next request (~5 s cold start).

---

## 7. Provision the TLS certificate

```sh
flyctl certs create demo.opensop.ai --app opensop-demo
```

---

## 8. Point DNS at the app

In your DNS registrar / DNS provider, add **one** of the following:

**Option A — CNAME (simplest, works for most providers):**

```
demo    CNAME    opensop-demo.fly.dev.
```

**Option B — A + AAAA records (required if the registrar forbids CNAME on the
apex / you need exact IPs):**

```sh
flyctl certs show demo.opensop.ai --app opensop-demo
```

Use the A and AAAA record values that command prints.

---

## 9. Verify

Certificate validation can take up to 5 minutes after DNS propagates.

```sh
# Poll until the cert is active:
flyctl certs show demo.opensop.ai --app opensop-demo

# Then confirm the app responds:
curl -i https://demo.opensop.ai/up
# Expected: HTTP/2 200
```

---

## Daily costs (rough estimate)

| Resource | Size | Approx. cost |
|---|---|---|
| App machine (shared-cpu-1x, 256 MB) | Billed per second when running | ~$0–3/mo at low traffic with `min_machines_running = 0` |
| Postgres cluster (shared-cpu-1x) | Always-on | See [Fly pricing](https://fly.io/docs/about/pricing/) |
| Postgres volume (1 GB) | Always-on | See [Fly pricing](https://fly.io/docs/about/pricing/) |

**Rule of thumb:** the smallest viable footprint (sleeping app + smallest
Postgres + 1 GB volume) is roughly **$5–10/month** based on Fly's published
rates. Verify current prices at <https://fly.io/docs/about/pricing/> before
committing — Fly adjusts pricing periodically.

To reduce Postgres cost further, consider the
[Fly Postgres HA](https://fly.io/docs/postgres/) single-node options or
sharing the primary deployment's cluster (create the demo databases there
instead of a dedicated cluster).

---

## Updating the demo

After the initial deploy, re-deploy with:

```sh
flyctl deploy --config fly.demo.toml
```

No other flags needed — secrets and attached databases persist between deploys.

---

## Troubleshooting

### `release_command` failed

```sh
flyctl releases --app opensop-demo
flyctl logs --app opensop-demo
```

Most common cause: a missing URL secret. Verify all three are set:

```sh
flyctl secrets list --app opensop-demo
# Should show: DATABASE_URL, CACHE_DATABASE_URL, QUEUE_DATABASE_URL,
#              RAILS_MASTER_KEY, OPENSOP_API_TOKEN, OPENSOP_BASE_URL
```

### App boots but `/up` returns 500

```sh
flyctl logs --app opensop-demo
```

Look for `ActiveRecord::ConnectionNotEstablished` or `PG::ConnectionBad` —
one of the three database URL secrets is missing or points at a database that
does not exist yet. Re-run steps 4–5.

### Need a shell on the machine

```sh
flyctl ssh console --app opensop-demo
```

From there: `./bin/rails console`, inspect `/rails/log/`, or
`psql $DATABASE_URL`.
