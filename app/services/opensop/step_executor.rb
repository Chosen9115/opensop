# frozen_string_literal: true

module Opensop
  # Dispatch table: maps a step `type:` string to the concrete executor class.
  module StepExecutor
    class UnknownType < StandardError; end

    MAPPING = {
      "form"         => "Opensop::StepExecutors::Form",
      "automated"    => "Opensop::StepExecutors::Automated",
      "judgment"     => "Opensop::StepExecutors::Judgment",
      "approval"     => "Opensop::StepExecutors::Approval",
      "webhook"      => "Opensop::StepExecutors::Webhook",
      "subprocess"   => "Opensop::StepExecutors::Subprocess",
      "notification" => "Opensop::StepExecutors::Notification",
      "wait"         => "Opensop::StepExecutors::Wait",
      "llm"          => "Opensop::StepExecutors::Llm"
    }.freeze

    module_function

    def for(step_type)
      class_name = MAPPING[step_type.to_s]
      raise UnknownType, "unknown step type #{step_type.inspect}" unless class_name
      class_name.constantize
    end
  end
end
