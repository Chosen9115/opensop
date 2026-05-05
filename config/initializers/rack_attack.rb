# Rate limiting for auth endpoints. Backed by Rails.cache (solid_cache).
#
# Each throttle returns 429 with a JSON body and a Retry-After header. Most
# rules scope by IP; the magic-link endpoint also scopes by email so a botnet
# that rotates IPs but targets one inbox is still bounded.

class Rack::Attack
  # Use Rails.cache (solid_cache) as the throttle store.
  Rack::Attack.cache.store = Rails.cache

  ### Magic link request — anti-enumeration / anti-spam

  # 5 magic-link requests per email per hour
  throttle("auth/magic_links/email", limit: 5, period: 1.hour) do |req|
    if req.path == "/auth/magic_links" && req.post?
      email = req.params["email"].to_s.strip.downcase
      email.presence
    end
  end

  # 10 magic-link requests per IP per hour
  throttle("auth/magic_links/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path == "/auth/magic_links" && req.post?
  end

  ### Passkey verification — anti-brute-force

  # 20 verify attempts per minute per IP
  throttle("auth/passkey/verify", limit: 20, period: 1.minute) do |req|
    req.ip if req.path == "/auth/passkey/verify" && req.post?
  end

  ### Passkey options — anti-challenge-fishing

  # 30 options requests per minute per IP
  throttle("auth/passkey/options", limit: 30, period: 1.minute) do |req|
    req.ip if req.path == "/auth/passkey/options" && req.post?
  end

  ### Passkey registration — defensive ceiling

  throttle("auth/passkey/registration_options", limit: 30, period: 1.minute) do |req|
    req.ip if req.path == "/auth/passkey/registration_options" && req.post?
  end

  throttle("auth/passkey/registration", limit: 30, period: 1.minute) do |req|
    req.ip if req.path == "/auth/passkey/registration" && req.post?
  end

  ### Account invitations — anti-spam
  #
  # rack-attack runs before authentication so we throttle by IP rather than
  # current_user.

  throttle("account/users/invite", limit: 10, period: 1.hour) do |req|
    req.ip if req.path == "/account/users" && req.post?
  end

  ### Custom 429 response

  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]
    headers = {
      "Content-Type" => "application/json",
      "Retry-After" => retry_after.to_s
    }
    body = { error: "rate_limited", retry_after: retry_after }.to_json
    [429, headers, [body]]
  end
end

# In test, Rack::Attack should be silent unless a spec explicitly enables it.
# We use the null cache store in test so throttles never trigger; specs that
# need to exercise the throttle point Rack::Attack.cache.store at a real cache
# for their duration.
if Rails.env.test?
  Rack::Attack.cache.store = ActiveSupport::Cache::NullStore.new
  Rack::Attack.enabled = false
end
