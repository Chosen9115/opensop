module SopApi
  # Load the seed customer-onboarding process into the DB.
  # Idempotent — safe to call in every example.
  def load_customer_onboarding!
    Opensop::Registry.load_file(
      Rails.root.join("processes/examples/customer-onboarding.sop.yaml")
    )
  end

  def load_appsignal_processes!
    %w[appsignal-responder appsignal-incident-fix appsignal-regression-check].each do |name|
      Opensop::Registry.load_file(
        Rails.root.join("processes/agent-kitchen/#{name}.sop.yaml")
      )
    end
  end
end

RSpec.configure do |config|
  config.include SopApi, type: :request
end
