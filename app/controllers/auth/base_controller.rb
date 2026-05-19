# frozen_string_literal: true

module Auth
  # Base controller for sign-in / magic-link / invitation flows. Inherits
  # from ActionController::Base directly (NOT Ui::ApplicationController) so
  # auth pages bypass the HTTP Basic gate AND the session gate — these
  # controllers ARE the auth, they cannot require auth to authenticate.
  class BaseController < ActionController::Base
    include Authenticatable

    layout "auth"
    protect_from_forgery with: :exception

    rescue_from ActiveRecord::RecordNotFound do
      render plain: I18n.t("opensop.auth.errors.token_invalid", default: "This link is invalid or expired."),
             status: :not_found
    end
  end
end
