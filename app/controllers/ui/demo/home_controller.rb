# frozen_string_literal: true

module Ui
  module Demo
    # Landing page for the public demo deployment.
    # Only wired as root when DEMO_MODE=true (see config/routes/ui.rb).
    class HomeController < Ui::ApplicationController
      # No activity rail on the homepage — it's a public-facing landing page.
      def show_rail?
        false
      end

      def show
        @api_token        = Opensop::DemoMode.api_token
        @reset_schedule   = Opensop::DemoMode::RESET_SCHEDULE_HUMAN
        @example_processes = begin
          Sop::Process.published.order(:name).limit(6)
        rescue ActiveRecord::StatementInvalid
          []
        end
      end
    end
  end
end
