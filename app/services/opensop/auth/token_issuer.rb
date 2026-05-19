module Opensop
  module Auth
    # Creates a MagicLinkToken row with a SHA-256 digest and returns the raw
    # token to the caller exactly once. The raw token is never persisted.
    #
    # Usage:
    #   raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "sign_in", requested_ip: req.remote_ip)
    #   # raw is the value to put in the email URL
    class TokenIssuer
      DEFAULT_TTLS = {
        "sign_in"    => 15.minutes,
        "recovery"   => 15.minutes,
        "invitation" => 7.days
      }.freeze

      def self.call(user:, purpose:, requested_ip: nil, expires_in: nil)
        new(user: user, purpose: purpose, requested_ip: requested_ip, expires_in: expires_in).call
      end

      def initialize(user:, purpose:, requested_ip:, expires_in:)
        @user = user
        @purpose = purpose.to_s
        @requested_ip = requested_ip
        @expires_in = expires_in || DEFAULT_TTLS.fetch(@purpose) { 15.minutes }
      end

      def call
        raw = SecureRandom.urlsafe_base64(32)
        digest = Digest::SHA256.hexdigest(raw)
        @user.magic_link_tokens.create!(
          token_digest: digest,
          purpose: @purpose,
          expires_at: @expires_in.from_now,
          requested_ip: @requested_ip
        )
        raw
      end
    end
  end
end
