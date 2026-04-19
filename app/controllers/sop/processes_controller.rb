module Sop
  # GET /sop/:name/schema — returns the full YAML-derived process definition
  # as JSON. Clients use this to understand inputs, outputs, and step shapes.
  class ProcessesController < ApplicationController
    def schema
      process = find_process!
      render json: process.definition
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
