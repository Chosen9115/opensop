# frozen_string_literal: true

require "openssl"
require "base64"

module Opensop
  # HMAC signature verification for inbound trigger webhooks.
  #
  # Third-party providers (Cal.com, Stripe, Typeform, HubSpot, etc.) sign
  # their webhook payloads with HMAC so the receiver can verify that the
  # request really came from them. Each provider names the header and
  # encoding differently — this module abstracts that.
  #
  # Process YAML declares the auth config under `trigger.auth`:
  #
  #   trigger:
  #     type: webhook
  #     auth:
  #       scheme: hmac-sha256              # only supported scheme in v0.2
  #       secret_env: CAL_WEBHOOK_SECRET   # env var holding the shared secret
  #       header: X-Cal-Signature-256      # header the provider sends
  #       encoding: hex                    # hex | base64 (default: hex)
  #       prefix: "sha256="                # optional; stripped before compare
  #
  # At runtime, `TriggersController` calls `WebhookAuth.verify!(config:, headers:, body:)`
  # which either returns silently (verification succeeded) or raises
  # InvalidSignature.
  module WebhookAuth
    class InvalidSignature < StandardError; end
    class MisconfiguredAuth < StandardError; end

    ALLOWED_SCHEMES = %w[hmac-sha256].freeze
    ALLOWED_ENCODINGS = %w[hex base64].freeze

    module_function

    # config: the `auth:` hash from the trigger block.
    # headers: a hash-like object (e.g. ActionDispatch::Http::Headers).
    # body: the raw request body as a String.
    def verify!(config:, headers:, body:)
      scheme = config["scheme"].to_s
      unless ALLOWED_SCHEMES.include?(scheme)
        raise MisconfiguredAuth, "unsupported scheme #{scheme.inspect} (allowed: #{ALLOWED_SCHEMES.join(", ")})"
      end

      secret = resolve_secret(config)
      header_name = config["header"].to_s
      raise MisconfiguredAuth, "trigger.auth.header is required" if header_name.empty?

      presented = headers[header_name].to_s
      raise InvalidSignature, "missing #{header_name} header" if presented.empty?

      presented = strip_prefix(presented, config["prefix"])
      expected = compute_signature(scheme, secret, body, config["encoding"] || "hex")

      unless ActiveSupport::SecurityUtils.secure_compare(presented, expected)
        raise InvalidSignature, "signature mismatch"
      end

      true
    end

    def resolve_secret(config)
      env_key = config["secret_env"].to_s
      raise MisconfiguredAuth, "trigger.auth.secret_env is required" if env_key.empty?

      secret = ENV[env_key]
      raise MisconfiguredAuth, "ENV[#{env_key.inspect}] is not set" if secret.nil? || secret.empty?
      secret
    end

    def strip_prefix(value, prefix)
      return value if prefix.nil? || prefix.to_s.empty?
      return value unless value.start_with?(prefix)
      value[prefix.length..]
    end

    def compute_signature(scheme, secret, body, encoding)
      unless ALLOWED_ENCODINGS.include?(encoding)
        raise MisconfiguredAuth, "unsupported encoding #{encoding.inspect} (allowed: #{ALLOWED_ENCODINGS.join(", ")})"
      end

      digest =
        case scheme
        when "hmac-sha256" then OpenSSL::HMAC.digest("SHA256", secret, body.to_s)
        end

      case encoding
      when "hex"    then digest.unpack1("H*")
      when "base64" then Base64.strict_encode64(digest)
      end
    end
  end
end
