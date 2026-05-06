# frozen_string_literal: true

# Rate-limiting rules for the public demo at demo.opensop.ai.
#
# All throttles are no-ops outside DEMO_MODE — production deployments of
# OpenSOP get rack-attack loaded but with zero rules attached, so behavior
# is identical to having no rate limiter at all.
#
# When DEMO_MODE=true, three throttles defend the demo from abuse:
#   - 60 req/min/IP across the SOP API
#   - 10 starts/hour/IP (the most expensive call — creates an instance + steps)
#   - 120 req/min/IP for the homepage and docs
# Plus a 5-minute IP ban for anyone exceeding 1000 req in 5 minutes (obvious abuse).

return unless defined?(Rack::Attack)

Rack::Attack.cache.store = Rails.cache

# Helper: only fire throttles in demo mode.
def demo_throttle?
  Opensop::DemoMode.enabled?
end

# 1) Generic SOP API throttle: 60 req/min per IP.
Rack::Attack.throttle("demo:sop:per-ip-per-minute", limit: 60, period: 60.seconds) do |req|
  req.ip if demo_throttle? && req.path.start_with?("/sop/")
end

# 2) Instance-start throttle: 10 starts/hour per IP. The /start endpoint is
#    the most expensive — creates a ProcessInstance + StepInstance graph.
Rack::Attack.throttle("demo:sop:starts-per-ip-per-hour", limit: 10, period: 1.hour) do |req|
  if demo_throttle? && req.post? && req.path.match?(%r{\A/sop/[a-z0-9][a-z0-9_-]*/start\z})
    req.ip
  end
end

# 3) Generic UI/docs throttle: 120 req/min per IP. More generous because
#    asset and page reloads are normal browsing behavior.
Rack::Attack.throttle("demo:ui:per-ip-per-minute", limit: 120, period: 60.seconds) do |req|
  req.ip if demo_throttle? && !req.path.start_with?("/sop/")
end

# 4) Hard ban: anyone exceeding 1000 requests in 5 minutes is obviously
#    abusing the demo. Block them for 5 minutes.
Rack::Attack.blocklist("demo:abuse-ip-ban") do |req|
  next false unless demo_throttle?
  Rack::Attack::Allow2Ban.filter("abuse:#{req.ip}", maxretry: 1000, findtime: 5.minutes, bantime: 5.minutes) do
    true
  end
end

# Custom 429 response — JSON for /sop, HTML for everything else.
Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  retry_after = match_data[:period] || 60
  if request.path.start_with?("/sop/")
    [
      429,
      {
        "Content-Type" => "application/json",
        "Retry-After" => retry_after.to_s
      },
      [%({"error":"rate_limit","message":"Demo is rate-limited. Retry after #{retry_after}s."})]
    ]
  else
    [
      429,
      { "Content-Type" => "text/html", "Retry-After" => retry_after.to_s },
      [%(<!doctype html><body style="font-family:system-ui;padding:3rem;text-align:center"><h1>Slow down</h1><p>The demo is rate-limited. Try again in #{retry_after} seconds.</p></body>)]
    ]
  end
end
