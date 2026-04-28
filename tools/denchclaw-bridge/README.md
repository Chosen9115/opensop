# DenchClaw Bridge

**PRIVATE — Coba fork only.**

A minimal Sinatra service that runs on the DenchClaw host and gives
Fly-hosted OpenSOP a network endpoint to insert leads into the local
DuckDB.

Exposed via Tailscale Funnel. Only `POST /leads` and `GET /healthz`
respond; every other path returns 404.

## Architecture

```
Cal.com booking
       │ HMAC-signed webhook
       ▼
Fly OpenSOP /sop/triggers/consult-request
       │ trigger verified, instance started
       ▼
consult-request.create-crm-record (webhook step)
       │ HTTPS via Tailscale Funnel
       ▼
Tailscale Funnel proxy
       │
       ▼
DenchClaw bridge (this service, localhost:9090)
       │ shell out to create-crm-record.rb
       ▼
DenchClaw DuckDB (v_people + v_deal rows, linked)
```

## Running it

### One-time setup

```bash
cd tools/denchclaw-bridge
bundle install
```

### Manual run (for testing)

```bash
export DENCHCLAW_BRIDGE_TOKEN=$(openssl rand -hex 32)
export DENCHCLAW_BRIDGE_SCRIPT="$(pwd)/../../processes/coba/steps/create-crm-record.rb"
bundle exec puma -b tcp://127.0.0.1:9090 config.ru
```

Then:

```bash
# Health check (no auth)
curl http://localhost:9090/healthz

# Insert a lead (bearer auth required)
curl -X POST http://localhost:9090/leads \
  -H "Authorization: Bearer $DENCHCLAW_BRIDGE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "lead_email":   "test@example.com",
    "lead_name":    "Test Lead",
    "lead_company": "Acme Corp",
    "lead_title":   "CFO",
    "source":       "linkedin",
    "platform_campaign_id": "urn:li:campaign:123",
    "enriched_company": ""
  }'
```

Expected response: `{"person_id":"...","deal_id":"...","was_duplicate":false}`.

### Persistent run via launchd (macOS)

`coba.denchclaw-bridge.plist` is the launchd plist. One-time install:

```bash
# Adjust WorkingDirectory inside the plist if your repo lives elsewhere.
cp coba.denchclaw-bridge.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/coba.denchclaw-bridge.plist

# Verify
launchctl list | grep denchclaw-bridge
curl http://localhost:9090/healthz
```

Logs go to `~/Library/Logs/denchclaw-bridge.{out,err}.log`.

To stop / uninstall:

```bash
launchctl unload ~/Library/LaunchAgents/coba.denchclaw-bridge.plist
rm ~/Library/LaunchAgents/coba.denchclaw-bridge.plist
```

### Tailscale Funnel setup

```bash
# Background funnel on port 9090
sudo tailscale funnel --bg 9090

# Confirm
tailscale funnel status
```

Funnel URL: `https://<your-laptop-hostname>.<your-tailnet>.ts.net`

Put this URL into Fly's `DENCHCLAW_BRIDGE_URL` secret for OpenSOP.

## Environment variables

| Var | Required | Purpose |
|---|---|---|
| `DENCHCLAW_BRIDGE_TOKEN` | yes | Bearer token. The same value must be set on the Fly `DENCHCLAW_BRIDGE_TOKEN` secret so OpenSOP can auth. Generate with `openssl rand -hex 32`. |
| `DENCHCLAW_BRIDGE_SCRIPT` | yes | Absolute path to `create-crm-record.rb`. Script must be executable (`chmod +x`). |
| `DENCHCLAW_BRIDGE_TIMEOUT` | no | Seconds before the script is killed (default 30). |

## Security notes

- Bearer token auth on `/leads`. Token is compared constant-time.
- `/healthz` is unauthenticated so Tailscale and external health checks don't need the token.
- The service refuses to start if `DENCHCLAW_BRIDGE_TOKEN` is empty or the script path isn't executable — fails closed.
- All non-matching paths return 404 with a minimal JSON body. No directory listing, no index, no static file serving.
- Inputs are JSON-parsed, never shelled as strings. The script receives inputs via stdin as JSON.

## Operational notes

- **DuckDB single-writer caveat:** if DenchClaw itself is writing to the DB while the bridge is inserting, you can get a lock conflict. Today this is rare (DenchClaw is read-mostly) but worth keeping in mind.
- **Laptop offline → step fails:** if the laptop is asleep or Tailscale Funnel isn't running when Cal.com fires a webhook, OpenSOP's `create-crm-record` step will fail. The instance pauses at `failed`; re-submit via `POST /sop/consult-request/:id/steps/create-crm-record/submit` once the laptop is back.
- **Log rotation:** launchd doesn't rotate logs. If the `.out.log` / `.err.log` grow, truncate them manually or add a newsyslog config.
