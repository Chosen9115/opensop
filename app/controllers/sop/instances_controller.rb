module Sop
  # Handles instance lifecycle over the API:
  #   POST /sop/:name/start            start an instance
  #   GET  /sop/:name/:id              show an instance
  #   GET  /sop/instances              list instances
  #   POST /sop/:name/:id/cancel       cancel an instance
  class InstancesController < ApplicationController
    MAX_LIMIT = 200
    DEFAULT_LIMIT = 50

    def start
      process = find_process!
      inputs = params_hash(:inputs)
      metadata = params_hash(:metadata).merge("actor" => current_actor)

      instance = Opensop::InstanceExecutor.start(
        process: process,
        inputs: inputs,
        metadata: metadata
      )

      render json: Sop::Serializers::InstanceSerializer.new(instance).as_json, status: :created
    end

    def show
      instance = find_instance!
      render json: Sop::Serializers::InstanceSerializer.new(instance).as_json
    end

    def index
      scope = Sop::Instance.order(created_at: :desc)
      scope = scope.where(state: params[:state]) if params[:state].present?
      scope = scope.where(process_name: params[:process]) if params[:process].present?

      limit = clamp_limit(params[:limit])
      offset = [params[:offset].to_i, 0].max
      total = scope.count

      instances = scope.limit(limit).offset(offset).map do |instance|
        Sop::Serializers::InstanceSerializer.new(instance, include_steps: false).as_json
      end

      render json: {
        instances: instances,
        total: total,
        limit: limit,
        offset: offset
      }
    end

    def cancel
      instance = find_instance!
      reason = params[:reason] || params.dig(:cancel, :reason)
      Opensop::InstanceExecutor.cancel!(instance, reason: reason)
      render json: Sop::Serializers::InstanceSerializer.new(instance.reload).as_json
    end

    private

    def find_process!
      scope = Sop::Process.published.where(name: params[:name])
      scope = scope.where(version: params[:version]) if params[:version].present?
      process = scope.to_a.max_by { |p| version_key(p.version) }
      raise ActiveRecord::RecordNotFound, "process #{params[:name].inspect} not found" unless process
      process
    end

    def find_instance!
      Sop::Instance.where(process_name: params[:name]).find(params[:id])
    end

    def version_key(version)
      Gem::Version.new(version.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end

    def clamp_limit(raw)
      value = raw.to_i
      value = DEFAULT_LIMIT if value <= 0
      [value, MAX_LIMIT].min
    end

    # Accepts nested or flat inputs. Returns a plain Hash with string keys.
    def params_hash(key)
      raw = params[key]
      return {} if raw.blank?
      if raw.respond_to?(:to_unsafe_h)
        raw.to_unsafe_h.deep_stringify_keys
      elsif raw.is_a?(Hash)
        raw.deep_stringify_keys
      else
        {}
      end
    end
  end
end
