FactoryBot.define do
  factory :auth_event do
    user
    kind { "signed_in" }
    ip_address { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (test)" }
    metadata { {} }

    AuthEvent::KINDS.each do |k|
      trait :"#{k}" do
        kind { k }
      end
    end
  end
end
