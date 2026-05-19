# OpenSOP first-run bootstrap initializer.
#
# Defers the actual work to Opensop::Auth::Bootstrap.run! so it is testable
# in isolation. The initializer just decides whether to invoke it on boot.
#
# Skipped during:
#   - asset precompilation (SECRET_KEY_BASE_DUMMY)
#   - any rails db:* task (so migrations don't fight the boot)
#   - when OPENSOP_BOOTSTRAP_EMAIL is unset

return if ENV["SECRET_KEY_BASE_DUMMY"].present?
return if defined?(Rails::Command) && ARGV.first.to_s.start_with?("db:")
return unless ENV["OPENSOP_BOOTSTRAP_EMAIL"].present?

Rails.application.config.after_initialize do
  Opensop::Auth::Bootstrap.run!
end
