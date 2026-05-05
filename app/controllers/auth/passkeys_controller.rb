# frozen_string_literal: true

module Auth
  # WebAuthn (passkey) ceremonies.
  #
  # Four endpoints:
  #
  #   POST /auth/passkey/registration_options — issue create options for the
  #     signed-in user. Stores challenge in session.
  #
  #   POST /auth/passkey/registration — verify attestation and persist a
  #     PasskeyCredential for the signed-in user.
  #
  #   POST /auth/passkey/options — PUBLIC. Issue get options for the supplied
  #     email (if any). Returns a non-enumerating response shape (always 200,
  #     always with a challenge).
  #
  #   POST /auth/passkey/verify — PUBLIC. Verify an assertion, look up the
  #     PasskeyCredential, increment sign_count, and call #sign_in to mint
  #     a session cookie.
  class PasskeysController < BaseController
    class InvalidChallenge < StandardError; end

    before_action :require_authentication, only: %i[registration_options registration]

    rescue_from InvalidChallenge do |e|
      render json: { error: "invalid_challenge", message: e.message }, status: :bad_request
    end

    # POST /auth/passkey/registration_options
    def registration_options
      user = current_user
      options = WebAuthn::Credential.options_for_create(
        user: {
          id: user.id,
          name: user.email,
          display_name: user.display_name.presence || user.email
        },
        exclude: user.passkey_credentials.pluck(:external_id),
        authenticator_selection: { user_verification: "preferred", resident_key: "preferred" }
      )
      session[:webauthn_registration_challenge] = options.challenge
      render json: options
    end

    # POST /auth/passkey/registration
    def registration
      user = current_user
      challenge = session.delete(:webauthn_registration_challenge)
      raise InvalidChallenge, "missing registration challenge" if challenge.blank?

      webauthn_credential = WebAuthn::Credential.from_create(passkey_params[:credential])
      webauthn_credential.verify(challenge)

      if user.passkey_credentials.exists?(external_id: webauthn_credential.id)
        return render json: { error: "duplicate_credential" }, status: :conflict
      end

      transports = Array(webauthn_credential.response.transports).compact.presence || []

      credential = user.passkey_credentials.create!(
        external_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count,
        nickname: passkey_params[:nickname].presence || default_nickname(request),
        transports: transports
      )

      Opensop::Auth::EventRecorder.call(
        kind: :passkey_registered,
        user: user,
        request: request,
        metadata: { passkey_credential_id: credential.id, nickname: credential.nickname }
      )

      render json: {
        id: credential.id,
        external_id: credential.external_id,
        nickname: credential.nickname,
        created_at: credential.created_at
      }, status: :created
    rescue WebAuthn::Error => e
      Rails.logger.warn("[Auth::Passkeys] registration verify failed: #{e.class}: #{e.message}")
      render json: { error: "registration_failed", message: e.message }, status: :unprocessable_entity
    end

    # POST /auth/passkey/options (PUBLIC)
    def options
      email = params[:email].to_s.strip.downcase
      user = User.find_by(email: email) if email.present?

      allow = if user
                user.passkey_credentials.pluck(:external_id)
              else
                []
              end

      options = WebAuthn::Credential.options_for_get(
        allow: allow,
        user_verification: "preferred"
      )
      session[:webauthn_authentication_challenge] = options.challenge
      render json: options
    end

    # POST /auth/passkey/verify (PUBLIC)
    def verify
      challenge = session.delete(:webauthn_authentication_challenge)
      raise InvalidChallenge, "missing authentication challenge" if challenge.blank?

      webauthn_credential = WebAuthn::Credential.from_get(passkey_params[:credential])
      stored = PasskeyCredential.find_by(external_id: webauthn_credential.id)
      return render(json: { error: "unknown_credential" }, status: :unauthorized) unless stored

      begin
        webauthn_credential.verify(
          challenge,
          public_key: stored.public_key,
          sign_count: stored.sign_count
        )
      rescue WebAuthn::SignCountVerificationError => e
        Rails.logger.error(
          "[Auth::Passkeys] sign_count regression — possible cloned credential: " \
          "external_id=#{stored.external_id.to_s.first(20)}…"
        )
        Opensop::Auth::EventRecorder.call(
          kind: :cloned_credential_detected,
          user: stored.user,
          request: request,
          metadata: { passkey_credential_id: stored.id, error: e.message }
        )
        return render(json: { error: "cloned_credential" }, status: :unauthorized)
      end

      stored.update!(
        sign_count: webauthn_credential.sign_count,
        last_used_at: Time.current
      )

      sign_in(stored.user, via: "passkey")

      render json: { redirect_to: safe_return_to(params[:return_to]) }
    rescue WebAuthn::Error => e
      Rails.logger.warn("[Auth::Passkeys] verify failed: #{e.class}: #{e.message}")
      Opensop::Auth::EventRecorder.call(
        kind: :passkey_assertion_failed,
        user: nil,
        request: request,
        metadata: { error: e.message, error_class: e.class.name }
      )
      render json: { error: "verification_failed", message: e.message }, status: :unauthorized
    end

    private

    def passkey_params
      params.permit(:nickname, :return_to, :email, credential: {})
    end

    def default_nickname(request)
      ua = request.user_agent.to_s
      case ua
      when /macintosh/i then "Mac"
      when /iphone/i    then "iPhone"
      when /ipad/i      then "iPad"
      when /android/i   then "Android"
      when /windows/i   then "Windows"
      else                   "New passkey"
      end
    end

    def safe_return_to(path)
      return "/dashboard" if path.blank?
      return path if path.start_with?("/") && !path.start_with?("//")
      "/dashboard"
    end
  end
end
