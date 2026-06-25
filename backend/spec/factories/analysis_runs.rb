FactoryBot.define do
  factory :analysis_run do
    association :submission
    runner { 'rubocop' }
    status { :pending }
    exit_code { nil }
    duration_ms { nil }
    stdout_excerpt { nil }
    stderr_excerpt { nil }
    started_at { nil }
    finished_at { nil }

    trait :succeeded do
      status { :succeeded }
      exit_code { 0 }
      duration_ms { 500 }
      started_at { 1.minute.ago }
      finished_at { Time.current }
    end

    trait :failed do
      status { :failed }
      exit_code { 2 }
      duration_ms { 100 }
      started_at { 1.minute.ago }
      finished_at { Time.current }
    end
  end
end
