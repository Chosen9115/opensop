# frozen_string_literal: true

module Ui
  module Account
    # Admin management. Lists all administrators, lets the signed-in admin
    # invite new ones (issues a 7-day invitation token via TokenIssuer and
    # delivers via Mailer), and lets them remove other admins. Self-removal
    # and last-admin removal are blocked.
    class UsersController < BaseController
      def index
        load_users
        @new_user = User.new
      end

      def create
        attrs = user_params
        normalized_email = attrs[:email].to_s.strip.downcase

        if User.exists?(email: normalized_email)
          load_users
          @new_user = User.new(attrs)
          @new_user.errors.add(:email, t("opensop.auth.account.users.flash.email_taken"))
          flash.now[:alert] = t("opensop.auth.account.users.flash.email_taken")
          render :index, status: :unprocessable_entity and return
        end

        user = User.new(attrs.merge(role: "admin"))
        unless user.save
          load_users
          @new_user = user
          flash.now[:alert] = user.errors.full_messages.to_sentence
          render :index, status: :unprocessable_entity and return
        end

        raw = Opensop::Auth::TokenIssuer.call(
          user: user,
          purpose: "invitation",
          requested_ip: request.remote_ip
        )
        Opensop::Auth::Mailer.send_invitation(
          user: user,
          raw_token: raw,
          host: request.base_url,
          inviter: current_user
        )

        invite_metadata = { invited_email: user.email, invited_by: current_user.id }
        Opensop::Auth::EventRecorder.call(
          kind: :user_invited,
          user: user,
          request: request,
          metadata: invite_metadata
        )
        Opensop::Auth::EventRecorder.call(
          kind: :invitation_sent,
          user: user,
          request: request,
          metadata: invite_metadata
        )

        redirect_to ui_account_users_path,
                    notice: t("opensop.auth.account.users.flash.invited", email: user.email)
      end

      def destroy
        target = User.find(params[:id])

        if target == current_user
          redirect_to ui_account_users_path,
                      alert: t("opensop.auth.account.users.flash.self_removal_blocked") and return
        end

        if User.where(role: "admin").count <= 1
          redirect_to ui_account_users_path,
                      alert: t("opensop.auth.account.users.flash.last_admin_blocked") and return
        end

        email = target.email
        target_id = target.id
        target.destroy!

        Opensop::Auth::EventRecorder.call(
          kind: :user_removed,
          user: current_user,
          request: request,
          metadata: { removed_user_id: target_id, removed_email: email, removed_by: current_user.id }
        )

        redirect_to ui_account_users_path,
                    notice: t("opensop.auth.account.users.flash.removed", email: email)
      end

      private

      def load_users
        @users = User
                 .left_outer_joins(:passkey_credentials)
                 .select("users.*, COUNT(passkey_credentials.id) AS passkey_count")
                 .group("users.id")
                 .order(:email)
      end

      def user_params
        params.require(:user).permit(:email, :display_name)
      end
    end
  end
end
