FactoryBot.define do
  factory :project do
    association :user
    sequence(:name) { |n| "#{Faker::App.name}-#{n}" }
    description { Faker::Lorem.sentence }
    language { 'ruby' }
    default_branch { 'main' }
    repo_url { nil }
    webhook_secret { nil }

    trait :with_webhook do
      repo_url { 'https://github.com/acme/widget' }
      webhook_secret { 'shh-secret' }
    end
  end
end
