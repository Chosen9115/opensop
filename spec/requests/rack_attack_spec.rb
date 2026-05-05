require "rails_helper"

# These specs explicitly enable Rack::Attack (it is disabled in the test
# environment by config/initializers/rack_attack.rb so other specs aren't
# affected by throttles). Each example uses a fresh in-memory store and
# clears it on teardown so examples don't leak counters across each other.
RSpec.describe "Rate limiting", type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  after do
    Rack::Attack.cache.store.clear if Rack::Attack.cache.store.respond_to?(:clear)
    Rack::Attack.enabled = false
  end

  describe "POST /auth/magic_links" do
    before do
      # Magic-link creation triggers an email send for known users; stub the
      # mailer so the throttle test isn't coupled to delivery infrastructure.
      allow(Opensop::Auth::Mailer).to receive(:send_magic_link).and_return({ id: "stub" })
    end

    it "throttles to 5 per email per hour" do
      5.times do
        post "/auth/magic_links", params: { email: "rate@example.com" }
        expect(response).to have_http_status(:ok)
      end

      post "/auth/magic_links", params: { email: "rate@example.com" }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
      expect(response.body).to include("rate_limited")
    end

    it "throttles to 10 per IP per hour across emails" do
      10.times do |i|
        post "/auth/magic_links", params: { email: "person#{i}@example.com" }
        expect(response).to have_http_status(:ok)
      end

      post "/auth/magic_links", params: { email: "spillover@example.com" }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "POST /auth/passkey/options" do
    it "throttles to 30 per minute per IP" do
      30.times do
        post "/auth/passkey/options", params: { email: "x@example.com" }
        expect(response).to have_http_status(:ok)
      end

      post "/auth/passkey/options", params: { email: "x@example.com" }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to be_present
    end
  end

  describe "non-auth paths" do
    it "does not rate-limit /up (health check)" do
      50.times do
        get "/up"
      end

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
