# frozen_string_literal: true

module Auth
  # Sign-in form (GET /auth/sign_in) and sign-out (DELETE /auth/sign_out).
  class SessionsController < BaseController
    def new
      redirect_to "/dashboard" and return if signed_in?
      @return_to = params[:return_to].presence
    end

    def destroy
      sign_out
      redirect_to auth_sign_in_path,
                  notice: I18n.t("opensop.auth.flash.signed_out", default: "Signed out.")
    end
  end
end
