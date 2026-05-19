FactoryBot.define do
  factory :auth_session do
    user
    transient { raw_token { SecureRandom.urlsafe_base64(32) } }
    token_digest { Digest::SHA256.hexdigest(raw_token) }
    user_agent { "Mozilla/5.0 (test)" }
    ip_address { "127.0.0.1" }
    expires_at { 30.days.from_now }
  end
end
