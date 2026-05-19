FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "admin#{n}@example.com" }
    display_name { "Admin User" }
    role { "admin" }
  end
end
