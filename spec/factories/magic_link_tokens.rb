FactoryBot.define do
  factory :magic_link_token do
    user
    transient { raw_token { SecureRandom.urlsafe_base64(32) } }
    token_digest { Digest::SHA256.hexdigest(raw_token) }
    purpose { "sign_in" }
    expires_at { 15.minutes.from_now }

    trait :recovery do
      purpose { "recovery" }
    end

    trait :invitation do
      purpose { "invitation" }
      expires_at { 7.days.from_now }
    end

    trait :consumed do
      consumed_at { Time.current }
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end
  end
end
