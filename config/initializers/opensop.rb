# frozen_string_literal: true

# Boot-time loader for the Opensop tool registry (SPEC-v0.2 §2.6).
#
# Always safe: built-ins are registered even when no config file exists.
# A workspace may opt in to custom tools by adding an `opensop.config.yaml`
# at the repo root (see `opensop.config.yaml.example` for the format).
Rails.application.config.after_initialize do
  Opensop::ToolRegistry.load!
end
