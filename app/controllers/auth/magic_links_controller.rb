# frozen_string_literal: true

module Auth
  # Magic-link request and consumption.
  #
  # POST /auth/magic_links — accepts an email + optional purpose. ALWAYS
  # returns the same "check your email" response regardless of whether the
  # email matches a real user (no enumeration). Only emits an email when a
  # user actually exists.
  #
  # GET /auth/magic_links/:token — consumes the token (if usable AND its
  # purpose is sign_in or recovery), creates a session, and redirects to
  # /dashboard. Invitation-purpose tokens are routed through the dedicated
  # InvitationsController instead.
  class MagicLinksController < BaseController
    # POST /auth/magic_links
    def create
      email = params[:email].to_s.strip.downcase
      purpose = params[:purpose].presence_in(%w[sign_in recovery]) || "sign_in"
      user = User.find_by(email: email) if email.present?

      raw = nil
      if user
        raw = Opensop::Auth::TokenIssuer.call(
          user: user,
          purpose: purpose,
          requested_ip: request.remote_ip
        )
        Opensop::Auth::Mailer.send_magic_link(
          user: user,
          raw_token: raw,
          purpose: purpose,
          host: request.base_url
        )
      end

      # Always record a magic_link_requested event — including for unknown
      # emails (user is nil). This is the audit signal for "someone tried
      # to magic-link this address."
      Opensop::Auth::EventRecorder.call(
        kind: :magic_link_requested,
        user: user,
        request: request,
        metadata: { email: email, purpose: purpose, user_found: user.present? }
      )

      # Recovery initiation is its own event so we can alarm on it.
      if purpose == "recovery"
        Opensop::Auth::EventRecorder.call(
          kind: :recovery_initiated,
          user: user,
          request: request,
          metadata: { email: email, user_found: user.present? }
        )
      end

      # Identical response regardless of whether the email matched a user.
      @email = email

      # Development-only DX: surface the magic link on the page so contributors
      # don't have to grep the log or open tmp/ to find it. Guarded by BOTH
      # Rails.env.development? AND the mailer being in log mode — production
      # is structurally incapable of leaking the URL even if the env is
      # misconfigured.
      if raw && Rails.env.development? && mailer_in_log_mode?
        @dev_magic_link_url = "#{request.base_url}/auth/magic_links/#{raw}"
      end

      render :create
    end

    # GET /auth/magic_links/:token
    def show
      token = MagicLinkToken.from_token(params[:token])
      unless token && %w[sign_in recovery].include?(token&.purpose)
        Opensop::Auth::EventRecorder.call(
          kind: :magic_link_expired,
          user: token&.user,
          request: request,
          metadata: { reason: token ? "wrong_purpose" : "not_found" }
        )
        raise ActiveRecord::RecordNotFound
      end

      via = token.purpose == "recovery" ? "recovery" : "magic_link"

      ActiveRecord::Base.transaction do
        token.consume!
        sign_in(token.user, via: via)
      end

      Opensop::Auth::EventRecorder.call(
        kind: :magic_link_consumed,
        user: token.user,
        request: request,
        metadata: { purpose: token.purpose }
      )

      if token.purpose == "recovery"
        redirect_to "/dashboard",
                    notice: I18n.t("opensop.auth.flash.recovered",
                                   default: "You're signed in. Manage your passkeys at /account/passkeys (coming soon).")
      else
        redirect_to "/dashboard",
                    notice: I18n.t("opensop.auth.flash.signed_in_register_passkey",
                                   default: "Signed in. Register a passkey on this device for faster sign-in next time.")
      end
    end

    private

    def mailer_in_log_mode?
      mode = ENV["OPENSOP_MAILER_MODE"].presence ||
             (Rails.env.production? ? "send" : "log")
      mode == "log"
    end
  end
end
