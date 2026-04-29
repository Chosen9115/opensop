# frozen_string_literal: true

require "yaml"

module Opensop
  # Scans a directory for `*.sop.yaml` template files and returns a normalized
  # array of template metadata hashes for the Templates admin page.
  #
  # No DB access — this is a pure file/YAML loader. Malformed YAML, missing
  # files, or unparseable mappings are logged and skipped (the page never
  # crashes on a single bad template).
  #
  # Example:
  #   Opensop::TemplateLoader.call
  #   # => [
  #   #   {
  #   #     path: "processes/v02-smoke-llm.sop.yaml",
  #   #     name: "v02-smoke-llm",
  #   #     version: "1.0",
  #   #     description: "...",
  #   #     inputs_count: 1,
  #   #     outputs_count: 2,
  #   #     steps_count: 1,
  #   #     raw_yaml: "<file contents>"
  #   #   },
  #   #   ...
  #   # ]
  class TemplateLoader
    GLOB = "**/*.sop.yaml"

    def self.call(root: default_root, logger: default_logger)
      new(root: root, logger: logger).call
    end

    def self.default_root
      Rails.root.join("processes")
    end

    def self.default_logger
      Rails.logger
    end

    def initialize(root:, logger:)
      @root = Pathname.new(root.to_s)
      @logger = logger
    end

    def call
      return [] unless @root.exist? && @root.directory?

      paths = Dir.glob(@root.join(GLOB)).sort
      paths.filter_map { |path| load_template(path) }
    end

    private

    def load_template(path)
      raw = File.read(path)
      parsed = YAML.safe_load(raw, permitted_classes: [ Symbol ])

      unless parsed.is_a?(Hash)
        @logger&.warn("[TemplateLoader] skipping #{path}: not a YAML mapping")
        return nil
      end

      process = parsed["process"]
      unless process.is_a?(Hash)
        @logger&.warn("[TemplateLoader] skipping #{path}: missing process: block")
        return nil
      end

      {
        path: relative_path(path),
        name: process["name"].to_s,
        version: process["version"].to_s,
        description: process["description"].to_s,
        inputs_count: count_array(process["inputs"]),
        outputs_count: count_array(process["outputs"]),
        steps_count: count_array(process["steps"]),
        raw_yaml: raw
      }
    rescue Psych::SyntaxError => e
      @logger&.warn("[TemplateLoader] skipping #{path}: malformed YAML (#{e.message})")
      nil
    rescue Errno::ENOENT, Errno::EACCES => e
      @logger&.warn("[TemplateLoader] skipping #{path}: #{e.message}")
      nil
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Rails.root).to_s
    rescue ArgumentError
      path.to_s
    end

    def count_array(value)
      value.is_a?(Array) ? value.size : 0
    end
  end
end
