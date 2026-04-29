module Ui
  # GET /api-docs — static reference page documenting the public OpenSOP HTTP
  # API exposed under `/sop/*`. No DB access; the endpoint list is hardcoded
  # to match `config/routes/sop.rb` so the page stays stable even if route
  # introspection changes shape.
  class ApiDocsController < ApplicationController
    ENDPOINTS = [
      { method: "GET",  path: "/sop/",                                       desc_key: "discovery" },
      { method: "GET",  path: "/sop/instances",                              desc_key: "instances_index" },
      { method: "POST", path: "/sop/webhooks/:callback_id",                  desc_key: "webhook_receive" },
      { method: "POST", path: "/sop/triggers/:process_name",                 desc_key: "trigger_receive" },
      { method: "GET",  path: "/sop/:name/schema",                           desc_key: "process_schema" },
      { method: "POST", path: "/sop/:name/start",                            desc_key: "process_start" },
      { method: "GET",  path: "/sop/:name/:id",                              desc_key: "instance_show" },
      { method: "POST", path: "/sop/:name/:id/cancel",                       desc_key: "instance_cancel" },
      { method: "GET",  path: "/sop/:name/:id/steps",                        desc_key: "steps_index" },
      { method: "POST", path: "/sop/:name/:id/steps/:step_id/submit",        desc_key: "step_submit" }
    ].freeze

    ENDPOINT_DESCRIPTIONS = {
      "discovery"        => "List all published processes (discovery).",
      "instances_index"  => "List all instances across processes.",
      "webhook_receive"  => "Receive an inbound webhook callback for a waiting step.",
      "trigger_receive"  => "Fire a trigger to start a new instance of a process.",
      "process_schema"   => "Return the full process definition (schema).",
      "process_start"    => "Start a new instance with the given inputs.",
      "instance_show"    => "Read the current state of an instance.",
      "instance_cancel"  => "Cancel a running instance.",
      "steps_index"      => "List the state of every step in an instance.",
      "step_submit"      => "Advance a step by submitting its outputs."
    }.freeze

    def index
      @endpoints = ENDPOINTS
      @endpoint_descriptions = ENDPOINT_DESCRIPTIONS
    end
  end
end
