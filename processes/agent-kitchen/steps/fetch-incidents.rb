#!/usr/bin/env ruby
# STUB — real implementation calls AppSignal GraphQL per project.
# Port from: src-tauri/src/appsignal_client.rs :: fetch_open_incidents
#
# Real query shape (one call per app_id):
#   query { app(id: $app_id) { incidents(state: "open", limit: 50) { ... } } }
#
# App IDs per project:
#   coba    → 6274502ed2a5e428ee8b9aee
#   pouch   → 69c5e79d9928e7e9167392d2
#   ddqpro  → 69e938d588e19a6f2a4a651b
#
# This stub returns one synthetic incident per project so the full flow is
# exercisable without a live AppSignal connection.

require "json"
require "time"

PROJECT_APP_IDS = {
  "coba"   => "6274502ed2a5e428ee8b9aee",
  "pouch"  => "69c5e79d9928e7e9167392d2",
  "ddqpro" => "69e938d588e19a6f2a4a651b"
}.freeze

inputs   = JSON.parse($stdin.read)
projects = Array(inputs["projects"])

incidents = projects.flat_map.with_index do |project, idx|
  app_id = PROJECT_APP_IDS[project]
  next [] unless app_id

  [
    {
      "incident_id"       => "stub-#{project}-#{idx + 1}",
      "incident_number"   => 9_000_000 + idx + 1,
      "app_id"            => app_id,
      "project"           => project,
      "repo"              => "coba-ai/#{project}",
      "project_path"      => "#{Dir.home}/workspace/workspace/#{project}",
      "action_name"       => "SomeController#show",
      "exception_name"    => "NoMethodError",
      "message"           => "undefined method `foo` for nil:NilClass",
      "first_seen"        => (Time.now - 86_400 * 7).iso8601,
      "last_seen"         => (Time.now - 3_600).iso8601,
      "state"             => "open",
      "occurrences_count" => 15,
      "tags"              => ["production"],
      "namespace"         => "web",
      "first_app_frame"   => {
        "file"   => "app/controllers/some_controller.rb",
        "line"   => 42,
        "method" => "show"
      },
      "app_frames" => [
        { "file" => "app/controllers/some_controller.rb", "line" => 42, "method" => "show" }
      ]
    }
  ]
end

$stdout.puts JSON.dump({
  "incidents"     => incidents,
  "total_fetched" => incidents.size
})
