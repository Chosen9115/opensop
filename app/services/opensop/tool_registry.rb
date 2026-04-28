# frozen_string_literal: true

require "yaml"

module Opensop
  # Registry of tools available to `llm` and `automated` steps (SPEC-v0.2 §2.6).
  #
  # The registry always exposes a fixed set of built-in tools (Read, Grep, Glob,
  # Write, WebFetch). If the workspace defines an `opensop.config.yaml` at the
  # repo root with a `tools:` section, those custom tools are merged on top of
  # the built-ins. A custom tool with the same name as a built-in overrides the
  # built-in (a warning is logged).
  #
  # Built-ins are lazily registered the first time the registry is accessed,
  # so `Opensop::ToolRegistry.tools` is always non-empty even without ever
  # calling `load!`.
  module ToolRegistry
    BUILTINS = {
      "Read"     => { handler: "builtin:read_file",  description: "Read a file from a permitted path" },
      "Grep"     => { handler: "builtin:grep",       description: "Search content with a regex" },
      "Glob"     => { handler: "builtin:glob",       description: "Find files matching a pattern" },
      "Write"    => { handler: "builtin:write_file", description: "Write a file to a permitted path" },
      "WebFetch" => { handler: "builtin:web_fetch",  description: "Fetch a URL and return body" }
    }.freeze

    DEFAULT_CONFIG_PATH_PROC = -> { Rails.root.join("opensop.config.yaml") }

    @mutex = Mutex.new
    @tools = nil

    module_function

    # Load the registry from a config file. Safe to call when the file is
    # absent — built-ins are still registered.
    def load!(config_path = nil)
      @mutex.synchronize do
        @tools = builtins_dup
        path = config_path || DEFAULT_CONFIG_PATH_PROC.call
        merge_config!(path) if File.exist?(path.to_s)
        @tools
      end
    end

    # All registered tools as a `Hash<String, Hash>` of `{ name => config }`.
    # Lazily registers built-ins on first access if `load!` has not been called.
    def tools
      ensure_loaded!
      @tools
    end

    # True when `name` resolves to a known tool.
    def allowed?(name)
      tools.key?(name.to_s)
    end

    # Returns the tool config hash for `name`, or nil if unknown.
    def lookup(name)
      tools[name.to_s]
    end

    # Clears all registered tools. The next access reloads built-ins
    # (and re-merges any config file present at the default path).
    def reset!
      @mutex.synchronize { @tools = nil }
    end

    # --- internal --------------------------------------------------------

    def ensure_loaded!
      return if @tools

      load!
    end
    private_class_method :ensure_loaded!

    def builtins_dup
      BUILTINS.each_with_object({}) { |(k, v), acc| acc[k] = v.dup }
    end
    private_class_method :builtins_dup

    def merge_config!(path)
      raw = File.read(path)
      data = YAML.safe_load(raw, permitted_classes: [], aliases: false) || {}
      custom = data["tools"]
      return unless custom.is_a?(Hash)

      custom.each do |name, config|
        key = name.to_s
        if BUILTINS.key?(key)
          logger&.warn(
            "[Opensop::ToolRegistry] custom tool #{key.inspect} overrides built-in (from #{path})"
          )
        end
        @tools[key] = symbolize_top_level(config)
      end
    end
    private_class_method :merge_config!

    def symbolize_top_level(config)
      return config unless config.is_a?(Hash)

      config.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
    end
    private_class_method :symbolize_top_level

    def logger
      return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      nil
    end
    private_class_method :logger
  end
end
