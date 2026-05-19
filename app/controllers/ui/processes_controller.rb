module Ui
  # GET  /processes            — list all active process definitions (latest version per name)
  # GET  /processes/:name      — read-only view of a definition (optional ?version=)
  # POST /processes/:name/runs — start a new instance (Trigger run)
  class ProcessesController < ApplicationController
    UNGROUPED_KEY = "Ungrouped".freeze
    DEFAULT_UNIT_KEY = "General".freeze

    def index
      all_published = Sop::Process.published.order(:name)

      # Keep only the latest version per process name (Fix #1).
      # version_key uses Gem::Version for semver-aware comparison.
      by_name = all_published.group_by(&:name)
      @processes = by_name.map do |_name, versions|
        versions.max_by { |p| version_key(p.version) }
      end.sort_by(&:name)

      # Build a lookup for prior-version counts (Fix #1 affordance).
      @prior_version_counts = by_name.transform_values { |versions| versions.size - 1 }

      # Precompute counts per process for the view (Fix #2 — add :total bucket).
      counts = Sop::Instance.group(:process_name, :state).count
      @counts = Hash.new { |h, k| h[k] = { in_flight: 0, completed: 0, failed: 0, total: 0 } }
      counts.each do |(name, state), count|
        bucket =
          case state
          when "pending", "running" then :in_flight
          when "completed" then :completed
          when "failed" then :failed
          else next
          end
        @counts[name][bucket] += count
        @counts[name][:total] += count
      end

      # Decorate each process with its derived dept/unit so the view stays clean.
      @processes.each do |process|
        dept_key, dept_label = derive_dept(process)
        unit_key, unit_label = derive_unit(process)
        process.define_singleton_method(:_dept) { dept_label }
        process.define_singleton_method(:_unit) { unit_label }
        process.define_singleton_method(:_dept_key) { dept_key }
        process.define_singleton_method(:_unit_key) { unit_key }
      end

      # Build the dept -> unit -> processes tree.
      @tree = build_tree(@processes)

      # Active filter state from query string. Match by display name (key).
      @dept = nil
      @unit = nil
      if params[:dept].present? && @tree.key?(params[:dept])
        @dept = params[:dept]
        if params[:unit].present? && @tree[@dept][:units].key?(params[:unit])
          @unit = params[:unit]
        end
      end

      @filter_q = params[:q].to_s.strip

      # Compute the visible subset based on dept/unit/q filters.
      @visible = @processes.to_a
      if @dept
        @visible = @visible.select { |p| p._dept_key == @dept }
        @visible = @visible.select { |p| p._unit_key == @unit } if @unit
      end
      if @filter_q.present?
        needle = @filter_q.downcase
        @visible = @visible.select do |p|
          name_match = p.name.to_s.downcase.include?(needle)
          desc = (p.definition || {}).dig("process", "description").to_s.downcase
          name_match || desc.include?(needle)
        end
      end

      in_flight_total = @visible.sum { |p| (@counts[p.name] || {})[:in_flight] || 0 }
      @summary = {
        count: @visible.size,
        in_flight: in_flight_total,
        processes: @visible.size
      }
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

    def start_run
      scope = Sop::Process.published.where(name: params[:name])
      process = scope.to_a.max_by { |p| version_key(p.version) }
      raise ActiveRecord::RecordNotFound, "process #{params[:name].inspect} not found" unless process

      raw_inputs = params[:inputs] || {}
      inputs =
        if raw_inputs.respond_to?(:to_unsafe_h)
          raw_inputs.to_unsafe_h.deep_stringify_keys
        else
          raw_inputs.to_h.deep_stringify_keys
        end

      instance = Opensop::InstanceExecutor.start(
        process: process,
        inputs: inputs,
        metadata: { actor: "ui" }
      )
      redirect_to ui_instance_path(instance), notice: t("opensop.flash.run_started")
    rescue Opensop::InstanceExecutor::InvalidInputs => e
      redirect_to ui_process_path(name: params[:name]),
                  alert: t("opensop.errors.invalid_inputs", message: e.message)
    end

    private

    def version_key(version)
      Gem::Version.new(version.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end

    # Returns [key, label]. The key is what we filter by in the URL; the label
    # is what we render. We humanize labels but keep keys stable.
    def derive_dept(process)
      defn_dept = process.definition&.dig("process", "dept")
      if defn_dept.present?
        return [ humanize_token(defn_dept), humanize_token(defn_dept) ]
      end

      parts = split_name(process.name)
      if parts.size >= 2
        return [ humanize_token(parts[0]), humanize_token(parts[0]) ]
      end

      owner = process.owner.to_s.strip
      label = owner.present? ? humanize_token(owner) : UNGROUPED_KEY
      [ label, label ]
    end

    def derive_unit(process)
      defn_unit = process.definition&.dig("process", "unit")
      if defn_unit.present?
        return [ humanize_token(defn_unit), humanize_token(defn_unit) ]
      end

      parts = split_name(process.name)
      if parts.size >= 2
        return [ humanize_token(parts[1]), humanize_token(parts[1]) ]
      end

      [ DEFAULT_UNIT_KEY, DEFAULT_UNIT_KEY ]
    end

    def split_name(name)
      name.to_s.split(/[.\/]/).reject(&:empty?)
    end

    def humanize_token(token)
      token.to_s.tr("-_", " ").split(/\s+/).map(&:capitalize).join(" ")
    end

    def build_tree(processes)
      tree = {}
      processes.each do |p|
        dept_key = p._dept_key
        unit_key = p._unit_key
        tree[dept_key] ||= { name: p._dept, count: 0, units: {} }
        tree[dept_key][:count] += 1
        tree[dept_key][:units][unit_key] ||= { name: p._unit, count: 0, items: [] }
        tree[dept_key][:units][unit_key][:count] += 1
        tree[dept_key][:units][unit_key][:items] << p
      end

      # Sort dept keys, and sort units within each dept.
      tree.keys.sort.each_with_object({}) do |dk, sorted|
        dept = tree[dk]
        sorted_units = dept[:units].keys.sort.each_with_object({}) do |uk, h|
          h[uk] = dept[:units][uk]
        end
        sorted[dk] = dept.merge(units: sorted_units)
      end
    end
  end
end
