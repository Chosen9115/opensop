FactoryBot.define do
  factory :sop_schedule, class: "Sop::Schedule" do
    name { "Daily report" }
    description { "Generates the daily report" }
    process_name { "daily_report" }
    cron_expression { "0 9 * * 1-5" }
    inputs { {} }
    timezone { "UTC" }
    enabled { true }
  end
end
