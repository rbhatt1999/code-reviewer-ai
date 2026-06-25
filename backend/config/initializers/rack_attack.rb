class Rack::Attack
  # Use an explicit in-memory store so the throttle counter works even when
  # Rails.cache is :null_store (test env — config/environments/test.rb:29).
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Throttle the UNAUTHENTICATED GitHub webhook endpoint by client IP.
  # GitHub delivers from its own IP ranges, so keep the limit generous; the
  # purpose is to blunt abuse of an endpoint that skips authenticate_user!.
  throttle('webhooks/github/ip', limit: 60, period: 60.seconds) do |req|
    req.ip if req.post? && req.path == '/api/v1/webhooks/github'
  end
end
