# OpenSOP auth-bypass boot warning.
#
# Emits a prominent warning when OPENSOP_DISABLE_AUTH activates the guarded
# bypass (non-public deployment only) so operators cannot miss it in logs.
# Also warns when the flag was set but silently ignored because a public
# OPENSOP_RP_ID is configured.
#
# Skipped during asset precompilation.

return if ENV["SECRET_KEY_BASE_DUMMY"].present?

Rails.application.config.after_initialize do
  if Opensop::AuthMode.bypass?
    Rails.logger.warn(
      "*** AUTHENTICATION DISABLED — OPENSOP_DISABLE_AUTH is set; " \
      "anyone who can reach this server has full admin access. " \
      "Never use this on a public deployment. ***"
    )
  elsif Opensop::AuthMode.disable_requested?
    # Do not interpolate the OPENSOP_RP_ID value into the log line — keep
    # config values out of logs on principle (log-aggregator exposure +
    # log-injection via untrusted values). The operator knows their own RP_ID.
    Rails.logger.warn(
      "*** OPENSOP_DISABLE_AUTH was IGNORED because a public domain " \
      "(OPENSOP_RP_ID) is configured. Authentication remains enforced. ***"
    )
  end
end
