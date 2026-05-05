# frozen_string_literal: true

module Ui
  module Account
    # Base for all /account/* admin pages. Inherits Ui::ApplicationController
    # so the existing HTTP Basic + session-auth gates apply automatically.
    # Account pages render in focus mode (no right-hand activity rail) so the
    # forms and tables get the full content width.
    class BaseController < Ui::ApplicationController
      def show_rail?
        false
      end
    end
  end
end
