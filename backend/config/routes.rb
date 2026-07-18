require 'sidekiq/web'

Rails.application.routes.draw do
  # ── Sidekiq Web UI (admin, HTTP Basic Auth) ──────────────────────────────
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    expected_user = ENV.fetch('SIDEKIQ_WEB_USER', '')
    expected_pass = ENV.fetch('SIDEKIQ_WEB_PASSWORD', '')
    # FAIL CLOSED: if creds are not configured, deny ALL (an empty expected value would otherwise
    # authenticate a client sending blank user/pass). Request-time check (not a boot raise) so the
    # app still boots in test/CI where these env vars may be unset.
    if expected_user.empty? || expected_pass.empty?
      false
    else
      ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(username), Digest::SHA256.hexdigest(expected_user)
      ) &
        ActiveSupport::SecurityUtils.secure_compare(
          Digest::SHA256.hexdigest(password), Digest::SHA256.hexdigest(expected_pass)
        )
    end
  end
  mount Sidekiq::Web => '/admin/sidekiq'

  devise_for :users,
             path: 'api/v1/auth',
             path_names: { sign_in: 'sign_in', sign_out: 'sign_out', registration: '' },
             controllers: {
               sessions: 'api/v1/auth/sessions',
               registrations: 'api/v1/auth/registrations'
             }

  namespace :api do
    namespace :v1 do
      get 'auth/me', to: 'auth/profiles#show'

      resources :projects do
        resources :submissions, only: %i[index create]
        member do
          post :regenerate_webhook_secret
        end
      end

      resources :submissions, only: %i[show] do
        member do
          get :issues
          get :review
          get 'files', to: 'files#index'
          get 'files/*path', to: 'files#show', format: false, constraints: { path: /.+/ }
          # Increment 4: report export — exactly three literal-dot routes, NO bare `get 'report'`
          # (a bare report route compiles to report(.:format) and shadows .md/.pdf — proven empirically)
          get 'report.json', to: 'reports#json'
          get 'report.md',   to: 'reports#markdown'
          get 'report.pdf',  to: 'reports#pdf'
        end
      end

      # Increment 4: admin metrics
      namespace :admin do
        get 'metrics', to: 'metrics#show'
      end

      # Increment 4: GitHub webhook (unauthenticated, HMAC-verified)
      namespace :webhooks do
        post 'github', to: 'github#create'
      end

      get 'health', to: 'health#show'
    end
  end
end
