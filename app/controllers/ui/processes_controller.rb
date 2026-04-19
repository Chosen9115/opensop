module Ui
  # GET /processes       — list all active process definitions
  # GET /processes/:name — read-only view of a definition (optional ?version=)
  class ProcessesController < ApplicationController
    def index
      @processes = Sop::Process.published.order(:name)

      # Precompute counts per process for the view.
      counts = Sop::Instance.group(:process_name, :state).count
      @counts = Hash.new { |h, k| h[k] = { in_flight: 0, completed: 0, failed: 0 } }
      counts.each do |(name, state), count|
        bucket =
          case state
          when "pending", "running" then :in_flight
          when "completed" then :completed
          when "failed" then :failed
          else next
          end
        @counts[name][bucket] += count
      end
    end

    def show
      scope = Sop::Process.where(name: params[:name])
      scope = scope.where(version: params[:version]) if params[:version].present?
      @process = scope.to_a.max_by { |p| version_key(p.version) }
      raise ActiveRecord::RecordNotFound, "process #{params[:name].inspect} not found" unless @process

      @definition = @process.definition || {}
      @process_block = @definition["process"] || {}
      @versions = Sop::Process.where(name: params[:name]).order(:version).pluck(:version)
    end

    private

    def version_key(version)
      Gem::Version.new(version.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
