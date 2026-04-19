module Ui
  # Base controller for the admin UI.
  #
  # TODO: add authentication (e.g. Devise, Rails 8 authentication generator)
  # before this is exposed beyond localhost.
  class ApplicationController < ActionController::Base
    layout "application"

    rescue_from ActiveRecord::RecordNotFound do |ex|
      render plain: "Not found: #{ex.message}", status: :not_found
    end

    rescue_from Opensop::InstanceExecutor::InvalidInputs,
                Opensop::InstanceExecutor::InvalidTransition,
                Opensop::DefinitionParser::InvalidDefinition,
                Opensop::InputResolver::UnresolvedReference do |ex|
      redirect_back fallback_location: "/", alert: ex.message
    end

    # When the views specialist hasn't shipped templates yet, render a
    # lightweight placeholder so routes are still verifiable. Rails 8's
    # ImplicitRender emits `head :no_content` (204) when no template is
    # found, which hides routing/controller issues behind empty bodies.
    # We check for the template up front and substitute a helpful 200 if
    # none exists. Once real templates ship, `super` renders them normally
    # and this override becomes a no-op.
    def default_render
      if lookup_context.exists?(action_name, [self.class.controller_path], false)
        super
      else
        render plain: "UI routes OK (views pending): #{controller_name}##{action_name}", status: :ok
      end
    end
  end
end
