FactoryBot.define do
  factory :passkey_credential do
    user
    sequence(:external_id) { |n| "credential-id-#{n}-#{SecureRandom.hex(8)}" }
    public_key { "fake-cose-public-key-bytes" }
    sign_count { 0 }
    nickname { "Test passkey" }
    transports { %w[internal] }
  end
end
