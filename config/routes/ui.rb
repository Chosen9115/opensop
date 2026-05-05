# Authentication routes — sit OUTSIDE the :ui module scope so they have their
# own controller namespace (Auth::*) and route helpers (auth_*).
scope :auth, module: :auth, as: :auth do
  # Sign-in form (GET) and sign-out (DELETE).
  get    "sign_in",  to: "sessions#new",     as: :sign_in
  delete "sign_out", to: "sessions#destroy", as: :sign_out

  # Magic link request and consumption.
  post "magic_links",        to: "magic_links#create", as: :magic_links
  get  "magic_links/:token", to: "magic_links#show",   as: :magic_link

  # Invitation acceptance (Phase 2 will add passkey registration here).
  get  "invitations/:token", to: "invitations#show",   as: :invitation

  # Passkey ceremonies. /options and /verify are PUBLIC (pre-sign-in).
  # /registration_options and /registration require an active session.
  scope :passkey, as: :passkey do
    post "registration_options", to: "passkeys#registration_options", as: :registration_options
    post "registration",         to: "passkeys#registration",         as: :registration
    post "options",              to: "passkeys#options",              as: :options
    post "verify",               to: "passkeys#verify",               as: :verify
  end
end

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

  # Account / admin self-service. Three sibling pages: passkeys, users
  # (admins), and active sessions. All gated by the existing
  # Ui::ApplicationController auth chain.
  namespace :account do
    resources :passkeys, only: %i[index update destroy]
    resources :users, only: %i[index create destroy]
    resources :sessions, only: %i[index destroy] do
      collection do
        delete :destroy_others, path: "others"
      end
    end
  end
end
