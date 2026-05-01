# frozen_string_literal: true

# Refuse to boot a production process when the admin UI auth credentials
# aren't configured. The /api-docs site is intentionally public, but the
# rest of the admin UI (/dashboard, /processes, /instances, …) reads and
# mutates workspace state and must always sit behind a credential.
#
# Override path: set OPENSOP_UI_USER and OPENSOP_UI_PASSWORD in the
# deployment environment.
if Rails.env.production?
  if ENV["OPENSOP_UI_USER"].to_s.strip.empty? || ENV["OPENSOP_UI_PASSWORD"].to_s.strip.empty?
    raise(
      "[SECURITY] OPENSOP_UI_USER and OPENSOP_UI_PASSWORD must both be set in " \
      "production. The admin UI exposes process state and mutating actions; " \
      "refusing to boot without credentials configured."
    )
  end
end
