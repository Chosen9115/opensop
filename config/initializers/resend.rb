# Configure the Resend Ruby SDK with the API key from env. Boot is allowed
# without the key in dev/test (mailer falls back to "log" mode), but
# production fails closed in the Opensop::Auth::Mailer when it tries to
# send without a configured key.
require "resend"

Resend.api_key = ENV["RESEND_API_KEY"] if ENV["RESEND_API_KEY"].present?
