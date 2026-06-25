RSpec.configure do |config|
  # Keep the throttle OFF for the suite so the existing webhook request specs
  # (same IP + path) never trip it. The dedicated throttle spec turns it on.
  config.before(:suite) { Rack::Attack.enabled = false }
end
