module Opensop
  module Auth
    # OpenSOP first-run bootstrap. Called from the initializer at boot time.
    #
    # If `OPENSOP_BOOTSTRAP_EMAIL` is set and either no users exist or the
    # bootstrap user exists without any registered passkey, this issues a
    # one-time invitation token and surfaces the URL to:
    #   - Rails.logger (info)
    #   - tmp/opensop_first_login.txt (chmod 0600)
    #
    # Idempotent: regenerates the token if the bootstrap user has no passkeys
    # and no unconsumed/unexpired invitation. No-op once a passkey exists.
    class Bootstrap
      def self.run!
        new.run!
      end

      def run!
        return unless email_env.present?

        # If users exist but the bootstrap email is not among them, leave
        # the workspace alone — someone else has been provisioned.
        return if User.count.positive? && !User.exists?(email: email_env)

        user = User.find_or_create_by!(email: email_env) do |u|
          u.display_name = "Bootstrap admin"
          u.role = "admin"
        end

        # If the bootstrap user already has any passkey, the workspace is
        # initialized — leave it alone.
        return if user.passkey_credentials.exists?

        # If a usable invitation token already exists, don't issue another one.
        return if user.magic_link_tokens.usable.where(purpose: "invitation").exists?

        raw = Opensop::Auth::TokenIssuer.call(user: user, purpose: "invitation")
        host = ENV.fetch("OPENSOP_ORIGIN", "http://localhost:3000")
        url = "#{host}/auth/invitations/#{raw}"

        Rails.logger.info("=" * 72)
        Rails.logger.info("[OpenSOP] Bootstrap admin: #{email_env}")
        Rails.logger.info("[OpenSOP] First-login URL (valid 7 days): #{url}")
        Rails.logger.info("=" * 72)

        file = Rails.root.join("tmp", "opensop_first_login.txt")
        File.write(file, "#{url}\n")
        File.chmod(0o600, file)
        url
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
        Rails.logger.warn("[OpenSOP] Bootstrap skipped (DB not ready): #{e.class}: #{e.message}")
        nil
      end

      private

      def email_env
        @email_env ||= ENV["OPENSOP_BOOTSTRAP_EMAIL"].to_s.strip.downcase.presence
      end
    end
  end
end
