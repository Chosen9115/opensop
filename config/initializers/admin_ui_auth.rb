# frozen_string_literal: true

# Refuse to boot a production process when the admin UI auth credentials
# aren't configured. The /api-docs site is intentionally public, but the
# rest of the admin UI (/dashboard, /processes, /instances, …) reads and
# mutates workspace state and must always sit behind a credential.
#
# Override paths:
#   - set OPENSOP_UI_USER and OPENSOP_UI_PASSWORD in the deployment
#     environment (the standard production setup), OR
#   - set DEMO_MODE=true, in which case the admin UI is intentionally
#     public — the public demo at demo.opensop.ai relies on rack-attack
#     throttles and the DemoReadOnly controller concern (which blocks
#     process-definition mutations) instead of HTTP-basic auth, so all
#     mutation surfaces visitors can reach are already locked down.
#
# `SECRET_KEY_BASE_DUMMY` is set by Rails 8 during `assets:precompile` at
# image-build time so the app can boot without real secrets. We skip the
# credential check in that branch — runtime always has a real
# SECRET_KEY_BASE, so this only fires on the actual production process.
if Rails.env.production? &&
   ENV["SECRET_KEY_BASE_DUMMY"].to_s.strip.empty? &&
   !Opensop::DemoMode.enabled?
  if ENV["OPENSOP_UI_USER"].to_s.strip.empty? || ENV["OPENSOP_UI_PASSWORD"].to_s.strip.empty?
    raise(
      "[SECURITY] OPENSOP_UI_USER and OPENSOP_UI_PASSWORD must both be set in " \
      "production. The admin UI exposes process state and mutating actions; " \
      "refusing to boot without credentials configured. " \
      "(For a public demo deployment, set DEMO_MODE=true instead.)"
    )
  end
end
