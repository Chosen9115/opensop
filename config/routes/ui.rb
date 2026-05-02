# Admin UI routes. All actions render HTML (or Turbo Stream later).
scope module: :ui, as: :ui do
  root to: "dashboard#index"
  get "dashboard", to: "dashboard#index", as: :dashboard

  resources :processes,
            only: [ :index, :show ],
            param: :name,
            constraints: { name: /[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*/ } do
    post "runs", to: "processes#start_run", on: :member, as: :runs
  end

  resources :instances, only: [ :index, :show ] do
    member do
      post :cancel
    end
    post "steps/:step_id/submit", to: "steps#submit", as: :submit_step
  end

  # Tier 1 informational pages — read-only, no DB writes.
  get "/webhooks",  to: "webhooks#index",  as: :webhooks
  get "/costs",     to: "costs#index",     as: :costs
  get "/templates", to: "templates#index", as: :templates
  scope "/api-docs", as: :api_docs do
    get "/",               to: "api_docs#index",   as: ""
    get "guides/:slug",    to: "api_docs#guide",    as: :guide,
        constraints: { slug: /[a-z][a-z0-9_-]*/ }
    get "endpoints/:slug", to: "api_docs#endpoint", as: :endpoint,
        constraints: { slug: /[a-z][a-z0-9_-]*/ }
  end

  # Tier 2 informational pages.
  get "/metrics", to: "metrics#index", as: :metrics
  get "/agents",  to: "agents#index",  as: :agents

  # Tier 3 — Schedule (cron-driven recurring instances).
  get "/schedule", to: "schedules#index", as: :schedule
end
