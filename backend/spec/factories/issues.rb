FactoryBot.define do
  factory :issue do
    association :submission
    analysis_run { nil }
    source { :linter }
    rule_id { 'RuboCop/Style/StringLiterals' }
    severity { :low }
    category { :style }
    file_path { 'app/models/user.rb' }
    line_start { 1 }
    line_end { 1 }
    column_start { 1 }
    column_end { nil }
    message { 'Prefer single-quoted strings when you don\'t need string interpolation or special symbols.' }
    suggestion { nil }
    confidence { nil }
    dedup_key { Digest::SHA1.hexdigest("#{file_path}|#{line_start}|#{rule_id}|#{SecureRandom.hex(4)}") }

    trait :linter do
      source { :linter }
    end

    trait :llm do
      source { :llm }
      rule_id { 'LLM/N+1Query' }
      suggestion { 'Use includes to eager load associations.' }
      confidence { 0.85 }
    end
  end
end
