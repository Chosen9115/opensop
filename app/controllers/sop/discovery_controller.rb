module Sop
  # GET /sop/ — discovery endpoint.
  # Lists all active processes (latest version per name) with enough
  # metadata for an agent to pick one and fetch its full schema.
  class DiscoveryController < ApplicationController
    def index
      # Dedupe by name, keeping the row with the latest version per name.
      # Sort versions lexicographically is wrong; coerce to Gem::Version
      # when possible for stable ordering.
      latest_per_name = Sop::Process.published.group_by(&:name).map do |_name, procs|
        procs.max_by { |p| version_key(p.version) }
      end

      processes = latest_per_name.sort_by(&:name).map do |process|
        Sop::Serializers::ProcessSummarySerializer.new(process).as_json
      end

      render json: { processes: processes }
    end

    private

    def version_key(version)
      Gem::Version.new(version.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
