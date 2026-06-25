# Sidekiq is the async job runner for the 4-job review pipeline
# (IngestJob → StaticAnalysisJob → LLMReviewJob → AggregateReportJob).
# Jobs receive only primitive IDs — strict_args! catches any accidental
# attempt to pass an ActiveRecord object as an argument.

redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

Sidekiq.strict_args!
