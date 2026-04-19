FactoryBot.define do
  factory :sop_process, class: "Sop::Process" do
    sequence(:name) { |n| "test-process-#{n}" }
    version { "1.0" }
    description { "A test process" }
    owner { "test-team" }
    tags { [ "test", "automated" ] }
    status { "active" }
    definition do
      {
        "opensop" => "0.1",
        "process" => {
          "name" => name,
          "version" => version,
          "steps" => []
        }
      }
    end

    trait :deprecated do
      status { "deprecated" }
    end

    trait :archived do
      status { "archived" }
    end
  end
end
