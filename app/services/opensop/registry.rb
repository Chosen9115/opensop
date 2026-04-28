# frozen_string_literal: true

require "yaml"

module Opensop
  # Loads process definitions from the filesystem and upserts them
  # into the Sop::Process table. Definitions are keyed by (name, version).
  module Registry
    DEFAULT_PATH_PROC = -> { Rails.root.join("processes") }

    module_function

    def load_all(path = nil)
      path ||= DEFAULT_PATH_PROC.call
      base = Pathname.new(path)
      return [] unless base.exist?

      results = []
      Dir.glob(base.join("**/*.sop.yaml")).sort.each do |file|
        results << load_file(file)
      end
      results.compact
    end

    def load_file(path)
      raw = File.read(path)
      parser_result = Opensop::DefinitionParser.call(raw)
      definition = parser_result.value
      process_block = definition["process"]

      record = Sop::Process.find_or_initialize_by(
        name: process_block["name"],
        version: process_block["version"].to_s
      )

      # If the definition hasn't changed, skip.
      if record.persisted? && record.definition == definition
        Rails.logger.info("[Opensop::Registry] unchanged: #{process_block["name"]} v#{process_block["version"]} (#{path})")
        return record
      end

      record.assign_attributes(
        description: process_block["description"],
        definition: definition,
        owner: process_block["owner"],
        tags: Array(process_block["tags"]),
        status: "active"
      )
      record.save!
      Rails.logger.info("[Opensop::Registry] loaded: #{record.name} v#{record.version} (#{path})")
      record
    end

    def reload!(path = nil)
      load_all(path).size
    end
  end
end
