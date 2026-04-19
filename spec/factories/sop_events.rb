FactoryBot.define do
  factory :sop_event, class: "Sop::Event" do
    association :instance, factory: :sop_instance
    event_type { "instance.started" }
    actor { "system" }
    data { {} }

    trait :step_completed do
      event_type { "step.completed" }
      step_id { "step-1" }
    end

    trait :step_escalated do
      event_type { "step.escalated" }
      step_id { "step-1" }
    end

    trait :instance_completed do
      event_type { "instance.completed" }
    end

    trait :instance_failed do
      event_type { "instance.failed" }
    end
  end
end
