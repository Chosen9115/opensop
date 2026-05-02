# frozen_string_literal: true

module Ui
  module ApiDocs
    # Single source of truth for the API reference site's navigation structure.
    # The controller, sidebar partial, and routing constraints all derive from here.
    module Catalog
      GUIDES = [
        { slug: "quickstart",     label: "Quickstart" },
        { slug: "authentication", label: "Authentication" },
        { slug: "process-format", label: "Process format" },
        { slug: "errors",         label: "Errors" },
        { slug: "versioning",     label: "Versioning" }
      ].freeze

      ENDPOINT_SECTIONS = [
        { key: :discovery, label: "Discovery", endpoints: [
            { slug: "list-processes",   method: "GET",  path: "/sop/",                                      summary_key: "list_processes" },
            { slug: "process-schema",   method: "GET",  path: "/sop/:name/schema",                          summary_key: "process_schema" }
          ] },
        { key: :processes, label: "Processes", endpoints: [
            { slug: "register-process", method: "POST", path: "/sop/processes/register",                    summary_key: "register_process" }
          ] },
        { key: :instances, label: "Instances", endpoints: [
            { slug: "list-instances",   method: "GET",  path: "/sop/instances",                             summary_key: "list_instances" },
            { slug: "start-instance",   method: "POST", path: "/sop/:name/start",                           summary_key: "start_instance" },
            { slug: "show-instance",    method: "GET",  path: "/sop/:name/:id",                             summary_key: "show_instance" },
            { slug: "cancel-instance",  method: "POST", path: "/sop/:name/:id/cancel",                      summary_key: "cancel_instance" }
          ] },
        { key: :steps, label: "Steps", endpoints: [
            { slug: "list-steps",       method: "GET",  path: "/sop/:name/:id/steps",                       summary_key: "list_steps" },
            { slug: "submit-step",      method: "POST", path: "/sop/:name/:id/steps/:step_id/submit",       summary_key: "submit_step" },
            { slug: "pending-steps",    method: "GET",  path: "/sop/steps/pending",                         summary_key: "pending_steps" }
          ] },
        { key: :webhook_triggers, label: "Webhook triggers", endpoints: [
            { slug: "fire-trigger",     method: "POST", path: "/sop/triggers/:process_name",                summary_key: "fire_trigger" }
          ] },
        { key: :webhook_callbacks, label: "Webhook callbacks", endpoints: [
            { slug: "deliver-callback", method: "POST", path: "/sop/webhooks/:callback_id",                 summary_key: "deliver_callback" }
          ] },
        { key: :metrics, label: "Metrics", endpoints: [
            { slug: "show-metrics",     method: "GET",  path: "/sop/metrics",                               summary_key: "show_metrics" }
          ] }
      ].freeze

      # --- Lookup helpers ---

      def self.guide(slug)
        GUIDES.find { |g| g[:slug] == slug }
      end

      def self.endpoint(slug)
        all_endpoints.find { |e| e[:slug] == slug }
      end

      # Returns the section hash { key:, label:, endpoints: [...] } that
      # contains the given endpoint slug, or nil. Used by the breadcrumb.
      def self.section_for_endpoint(slug)
        ENDPOINT_SECTIONS.find { |s| s[:endpoints].any? { |e| e[:slug] == slug } }
      end

      # Flat list of all endpoint slugs — used as a routing constraint.
      def self.endpoint_slugs
        all_endpoints.map { |e| e[:slug] }
      end

      # Flat list of all guide slugs — used as a routing constraint.
      def self.guide_slugs
        GUIDES.map { |g| g[:slug] }
      end

      # --- Private helpers ---

      def self.all_endpoints
        ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }
      end
      private_class_method :all_endpoints
    end
  end
end
