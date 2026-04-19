FactoryBot.define do
  factory :sop_instance, class: "Sop::Instance" do
    association :process, factory: :sop_process
    process_name { process&.name || "test-process" }
    process_version { process&.version || "1.0" }
    state { "pending" }
    inputs { {} }
    outputs { {} }
    metadata { {} }

    trait :running do
      state { "running" }
      started_at { Time.current }
    end

    trait :completed do
      state { "completed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end

    trait :failed do
      state { "failed" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error { "something went wrong" }
    end

    trait :cancelled do
      state { "cancelled" }
      started_at { 1.hour.ago }
      completed_at { Time.current }
    end
  end
end
