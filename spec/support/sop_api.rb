module SopApi
  # Load the seed customer-onboarding process into the DB.
  # Idempotent — safe to call in every example.
  def load_customer_onboarding!
    Opensop::Registry.load_file(
      Rails.root.join("processes/customer-onboarding.sop.yaml")
    )
  end
end

RSpec.configure do |config|
  config.include SopApi, type: :request
end
