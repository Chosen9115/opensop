# Deploying OpenSOP to Fly.io

This runbook walks through deploying OpenSOP to [Fly.io](https://fly.io)
using the `fly.toml` and `config/database.yml` already committed to the repo.

> **Heads up:** every step that calls `fly` / `flyctl` provisions or touches
> paid cloud resources. Read each command before you run it.

## 0. Prerequisites

1. [`flyctl` installed](https://fly.io/docs/hands-on/install-flyctl/).
2. `fly auth login` (one time).
3. `config/master.key` exists locally (check with `ls config/master.key`).
   If it's missing, you cannot decrypt production credentials — recover it
   from your password manager or re-generate credentials before going further.
4. You have a Fly organization that can create apps and Postgres clusters.

## 1. Launch the app (no deploy, keep our config)

```sh
fly launch --no-deploy --copy-config
```

- When asked **"Would you like to overwrite the existing fly.toml?"** answer
  **No**. We want the one in the repo.
- When asked **"Would you like to set up a Postgres database now?"** answer
  **No**. We'll create it in the next step so cache/queue DBs are easy to add.
- When asked about Redis / object storage, answer **No** (OpenSOP uses
  Solid Cache / Solid Queue — database-backed, no Redis needed).
- Confirm the app name and region. If you changed them, also update
  `app = ...` and `primary_region = ...` in `fly.toml` and commit the change.

## 2. Create the Postgres cluster

```sh
fly postgres create \
  --name opensop-db \
  --region iad \
  --initial-cluster-size 1 \
  --vm-size shared-cpu-1x \
  --volume-size 10
```

- Match the region to your app's `primary_region`.
- **This provisions paid infrastructure.** Even the smallest cluster
  accrues compute + volume cost beyond the free allowance.
- Save the connection string Fly prints at the end; you will need it in
  step 4 to derive `CACHE_DATABASE_URL` and `QUEUE_DATABASE_URL`.

## 3. Attach Postgres to the app

```sh
fly postgres attach opensop-db -a opensop
```

This creates a role named `opensop`, creates the `opensop` database on the
cluster, and sets `DATABASE_URL` as a secret on the app. That URL points at
the *primary* database (`opensop`). We still need separate databases for
Solid Cache and Solid Queue.

## 4. Create cache + queue databases and set their URLs

Open a psql session on the cluster:

```sh
fly postgres connect -a opensop-db
```

Then, inside psql:

```sql
CREATE DATABASE opensop_production_cache OWNER opensop;
CREATE DATABASE opensop_production_queue OWNER opensop;
\q
```

Now set the two additional URL secrets. They reuse the same host + credentials
as `DATABASE_URL`; only the trailing database name changes. Fly.io's attach
URLs look like `postgres://opensop:PASSWORD@opensop-db.flycast:5432/opensop`.
Replace the trailing `/opensop` with the new database names:

```sh
fly secrets set \
  CACHE_DATABASE_URL="postgres://opensop:PASSWORD@opensop-db.flycast:5432/opensop_production_cache" \
  QUEUE_DATABASE_URL="postgres://opensop:PASSWORD@opensop-db.flycast:5432/opensop_production_queue" \
  -a opensop
```

To recover the exact host and password later, run
`fly secrets list -a opensop` (shows digests only) or re-run
`fly postgres attach` against a throwaway app; easier to just save it the
first time.

## 5. Set the Rails master key

```sh
fly secrets set RAILS_MASTER_KEY="$(cat config/master.key)" -a opensop
```

## 6. Deploy

```sh
fly deploy
```

During deploy:

1. Fly builds the image from the repo's `Dockerfile`.
2. Spins up a release machine and runs `./bin/rails db:prepare` — this runs
   migrations for **all three** databases (primary, cache via
   `db/cache_migrate`, queue via `db/queue_migrate`) because the YAML
   configures all three connections.
3. Rolls out the web machine. Thruster listens on port 80 and Fly's proxy
   health-checks `/up` before shifting traffic.
4. Solid Queue runs as a Puma plugin on the web machine
   (`SOLID_QUEUE_IN_PUMA=true`).

## 7. Verify

```sh
fly status -a opensop
fly logs -a opensop
fly open -a opensop  # opens the deployed app in a browser
```

`GET /up` should return `200`.

## Scaling later

### Bump memory / CPU

Edit the `[[vm]]` block in `fly.toml` (e.g. `memory = "2gb"`) and
`fly deploy`, or scale imperatively:

```sh
fly scale vm shared-cpu-2x --memory 2048 -a opensop
```

### Keep one machine always warm

Edit `fly.toml`:

```toml
[http_service]
  min_machines_running = 1
```

Commit and `fly deploy`. Removes cold-start latency at the cost of always-on
compute.

### Split Solid Queue into its own process group

Running Solid Queue in-Puma is fine until background jobs start stealing
request-serving threads. When that happens:

1. Remove `SOLID_QUEUE_IN_PUMA=true` from `fly.toml`'s `[env]`.
2. Add a `[processes]` block to `fly.toml`, e.g.:

   ```toml
   [processes]
     app = "./bin/thrust ./bin/rails server"
     worker = "./bin/jobs"
   ```

3. Update `[http_service].processes` to `["app"]` (already the case).
4. Give the worker its own `[[vm]]` block if you want a different size.

See the Rails 8 guides for
[Solid Queue](https://github.com/rails/solid_queue) and Fly's
[process groups](https://fly.io/docs/apps/processes/) docs.

## Troubleshooting

### `release_command` failed

```sh
fly releases -a opensop
fly logs -a opensop
```

Most common cause: a migration error, or one of `DATABASE_URL` /
`CACHE_DATABASE_URL` / `QUEUE_DATABASE_URL` is missing or points at a
database that doesn't exist yet. `fly secrets list -a opensop` should show
all three.

### App boots but `/up` returns 500

Check the logs for `ActiveRecord::ConnectionNotEstablished` or
`PG::ConnectionBad`:

```sh
fly logs -a opensop
```

Usually one of the three URL secrets is missing or malformed. Re-run
step 4. Remember: Rails needs to connect to **all three** databases on
boot (primary + cache + queue).

### 502 from the Fly proxy

Means Fly can't reach the app on `internal_port`. Verify:

- `fly.toml` sets `internal_port = 80`.
- `PORT=80` is in `fly.toml`'s `[env]` (Thruster reads this).
- The Dockerfile still has `EXPOSE 80` and `CMD ["./bin/thrust", "./bin/rails", "server"]`.

If you changed any of the above, `fly deploy` again.

### Need a shell on the machine

```sh
fly ssh console -a opensop
```

From there you can run `./bin/rails console`, inspect logs at
`/rails/log/`, or `psql $DATABASE_URL`.

## Notes about what we are (and aren't) doing

- **Kamal is untouched.** `config/deploy.yml` and `.kamal/` still exist; a
  future Kamal deploy will continue to use `OPENSOP_DATABASE_PASSWORD`.
- **No volumes.** Postgres is on a separate managed cluster; the app
  machines are stateless.
- **No Redis.** Solid Cache and Solid Queue are both database-backed.
- **`bin/docker-entrypoint` also runs `db:prepare`** when the command is
  `./bin/rails server`. That's redundant with `[deploy].release_command`,
  but it's idempotent and acts as a safety net for hand-started containers.
