# Admin UI routes. All actions render HTML (or Turbo Stream later).
scope module: :ui, as: :ui do
  # Demo homepage — shown when DEMO_MODE=true; normal dashboard otherwise.
  # The constrained route must be declared first (Rails evaluates top-to-bottom).
  # We suppress the route name on the constrained entry so only the unconstrainted
  # "root" gets the canonical `ui_root` helper — both routes map to "/" but
  # the named helper always resolves to the dashboard, which is correct for
  # link_to/redirect_to usage inside the app.
  get "/", to: "demo/home#show",
      constraints: ->(_req) { Opensop::DemoMode.enabled? },
      as: :demo_home
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

  # Project documentation rendered from docs/*.md
  get "/docs(/*path)", to: "docs#show", as: :docs,
      constraints: { path: %r{[a-zA-Z0-9_\-/]+} },
      defaults: { path: "index" }
  # Bundled markdown — every guide and endpoint in one file. Defined BEFORE
  # the /api-docs scope so the explicit /api-docs.md path wins over the
  # scope's index route, which would otherwise greedily match `.md` as the
  # request format.
  get "/api-docs.md", to: "api_docs#bundled", as: :api_docs_bundled,
      defaults: { format: :md }

  scope "/api-docs", as: :api_docs do
    get "/",               to: "api_docs#index",   as: ""
    get "guides/:slug",    to: "api_docs#guide",    as: :guide,
        constraints: { slug: /[a-z][a-z0-9_-]*/ },
        format: false
    get "guides/:slug.md", to: "api_docs#guide",    as: :guide_md,
        constraints: { slug: /[a-z][a-z0-9_-]*/ },
        defaults: { format: :md }
    get "endpoints/:slug", to: "api_docs#endpoint", as: :endpoint,
        constraints: { slug: /[a-z][a-z0-9_-]*/ },
        format: false
    get "endpoints/:slug.md", to: "api_docs#endpoint", as: :endpoint_md,
        constraints: { slug: /[a-z][a-z0-9_-]*/ },
        defaults: { format: :md }
  end

  # llms.txt — discovery file for AI crawlers, points at the bundled MD.
  # Lives at the application root, not under /api-docs.
  get "/llms.txt", to: "api_docs#llms_txt", as: :llms_txt,
      defaults: { format: :text }

  # XML sitemap — every public docs URL, with xhtml:link alternates so
  # search-engine and AI crawlers see the .md mirror right next to the
  # HTML one. Lives at the application root.
  get "/sitemap.xml", to: "api_docs#sitemap", as: :sitemap,
      defaults: { format: :xml }

  # Tier 2 informational pages.
  get "/metrics", to: "metrics#index", as: :metrics
  get "/agents",  to: "agents#index",  as: :agents

  # Tier 3 — Schedule (cron-driven recurring instances).
  get "/schedule", to: "schedules#index", as: :schedule
end
