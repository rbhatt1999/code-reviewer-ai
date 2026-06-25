FactoryBot.define do
  factory :review do
    association :submission
    mode { :linter_only }
    summary { nil }
    scores { nil }
    total_issues { 0 }
    llm_attempts { 0 }
    llm_duration_ms { nil }
  end
end
