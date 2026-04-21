# /sop/* JSON API routes.
#
# Process names may only contain [a-z0-9_-], so the `:name` capture is
# constrained to avoid clashing with flat endpoints like `/sop/instances`.
scope :sop, as: :sop, module: :sop, defaults: { format: :json } do
  get "/", to: "discovery#index", as: :discovery
  get "/instances", to: "instances#index", as: :instances
  post "/webhooks/:callback_id", to: "webhooks#receive", as: :webhook
  post "/triggers/:process_name", to: "triggers#receive", as: :trigger

  constraints(name: /[a-z0-9][a-z0-9_-]*/) do
    scope "/:name" do
      get "/schema", to: "processes#schema", as: :process_schema
      post "/start", to: "instances#start", as: :process_start
      get "/:id", to: "instances#show", as: :process_instance
      post "/:id/cancel", to: "instances#cancel", as: :process_instance_cancel
      get "/:id/steps", to: "steps#index", as: :process_instance_steps
      post "/:id/steps/:step_id/submit", to: "steps#submit", as: :process_instance_step_submit
    end
  end
end
