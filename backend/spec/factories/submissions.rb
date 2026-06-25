FactoryBot.define do
  factory :submission do
    association :user
    association :project
    kind { :single_file }
    status { :pending }
    source_ref { 'test_file.rb' }
    blob_path { "storage/submissions/#{SecureRandom.uuid}/test_file.rb" }
    size_bytes { 1024 }
    language { 'ruby' }
    ast_summary { nil }
    error_message { nil }
    finished_at { nil }

    trait :completed do
      status { :completed }
      finished_at { Time.current }
    end

    trait :failed do
      status { :failed }
      error_message { 'Analysis failed' }
      finished_at { Time.current }
    end

    trait :with_issues do
      completed
      after(:create) do |submission|
        create_list(:issue, 2, :linter, submission: submission)
      end
    end
  end
end
