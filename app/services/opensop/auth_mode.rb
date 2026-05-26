# frozen_string_literal: true

module Opensop
  # Centralises the "is auth bypass active?" predicate for the guarded
  # OPENSOP_DISABLE_AUTH environment variable.
  #
  # All predicate methods are stateless pure ENV reads — no memoization at
  # class level — so the test suite can stub ENV per example safely.
  # Only +bypass_user+ touches the database.
  module AuthMode
    module_function

    TRUTHY_VALUES = %w[true 1 yes on].freeze
    LOCAL_RP_IDS  = %w[localhost 127.0.0.1].freeze
    private_constant :TRUTHY_VALUES, :LOCAL_RP_IDS

    # Returns true when OPENSOP_DISABLE_AUTH is set to a recognised truthy
    # string (case-insensitive, whitespace-tolerant).
    def disable_requested?
      TRUTHY_VALUES.include?(ENV["OPENSOP_DISABLE_AUTH"].to_s.strip.downcase)
    end

    # Returns true when OPENSOP_RP_ID is set to something other than
    # "localhost" or "127.0.0.1" — i.e. a real public deployment.
    # Unset or blank => false (local / not-yet-configured).
    def public_deployment?
      rp = ENV["OPENSOP_RP_ID"].to_s.strip.downcase
      rp.present? && !LOCAL_RP_IDS.include?(rp)
    end

    # Auth bypass is only allowed when explicitly requested AND the deployment
    # is not public. Public deployments must always enforce authentication.
    def bypass?
      disable_requested? && !public_deployment?
    end

    # Resolve the user to auto-login when bypass is active. Resolution order:
    #   1. User matching OPENSOP_BOOTSTRAP_EMAIL (case-insensitive)
    #   2. Oldest admin user
    #   3. Oldest user of any role
    #   4. nil
    #
    # Emails are stored downcased by the User model's before_validation hook,
    # so a case-insensitive WHERE covers any edge cases from direct DB writes.
    def bypass_user
      email = ENV["OPENSOP_BOOTSTRAP_EMAIL"].to_s.strip.downcase.presence

      if email
        user = User.where("LOWER(email) = ?", email).first
        return user if user
      end

      User.where(role: "admin").order(:created_at).first ||
        User.order(:created_at).first
    end
  end
end
