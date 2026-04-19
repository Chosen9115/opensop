FactoryBot.define do
  factory :sop_step, class: "Sop::Step" do
    association :instance, factory: :sop_instance
    sequence(:step_id) { |n| "step-#{n}" }
    step_name { "Test Step" }
    step_type { "automated" }
    state { "pending" }
    inputs { {} }
    outputs { {} }
    attempt { 1 }
    sequence(:position) { |n| n }

    trait :form do
      step_type { "form" }
    end

    trait :judgment do
      step_type { "judgment" }
    end

    trait :approval do
      step_type { "approval" }
    end

    trait :webhook do
      step_type { "webhook" }
    end

    trait :active do
      state { "active" }
      started_at { Time.current }
    end

    trait :completed do
      state { "completed" }
      started_at { 10.minutes.ago }
      completed_at { Time.current }
    end

    trait :waiting_for_input do
      state { "active" }
      sub_state { "waiting_for_input" }
      started_at { Time.current }
    end

    trait :waiting_for_callback do
      state { "active" }
      sub_state { "waiting_for_callback" }
      started_at { Time.current }
    end

    trait :escalated do
      state { "active" }
      sub_state { "escalated" }
      started_at { Time.current }
    end
  end
end
