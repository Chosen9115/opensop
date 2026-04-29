module Sop
  # GET  /sop/:name/schema       — returns the full process definition as JSON
  # POST /sop/processes/register — upsert a process from raw YAML
  class ProcessesController < ApplicationController
    def schema
      process = find_process!
      render json: process.definition
    end

    def register
      raw = params[:yaml].presence || request.raw_post
      if raw.blank?
        render json: { error: "missing_yaml", message: "provide YAML in the `yaml` param or as the raw request body" },
               status: :unprocessable_entity
        return
      end

      process = Opensop::Registry.load_yaml(raw.to_s, source: "api:#{current_actor}")

      render json: {
        name:        process.name,
        version:     process.version,
        description: process.description,
        owner:       process.owner,
        steps:       process.definition.dig("process", "steps")&.map { |s| s["id"] },
        status:      process.status
      }, status: :created
    end

    private

    def find_process!
      scope = Sop::Process.published.where(name: params[:name])
      scope = scope.where(version: params[:version]) if params[:version].present?

      process = scope.to_a.max_by { |p| version_key(p.version) }
      raise ActiveRecord::RecordNotFound, "process #{params[:name].inspect} not found" unless process
      process
    end

    def version_key(version)
      Gem::Version.new(version.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
