# frozen_string_literal: true

# Mark mutation endpoints as forbidden when DEMO_MODE is on. Instance
# lifecycle (start/submit/cancel) is intentionally exempt — visitors need
# to be able to drive instances through the engine to see what OpenSOP
# does. Only definition-level mutations are blocked, since they would
# permanently change the demo for everyone else until the daily 3:00 UTC
# reset.
#
# Usage:
#   class Sop::ProcessesController < ApplicationController
#     include DemoReadOnly
#     forbid_in_demo! :register, :update, :destroy
#   end
module DemoReadOnly
  extend ActiveSupport::Concern

  class_methods do
    def forbid_in_demo!(*actions)
      before_action :reject_in_demo, only: actions
    end
  end

  private

  def reject_in_demo
    return unless Opensop::DemoMode.enabled?

    if request.format.json? || request.path.start_with?("/sop/")
      render json: {
        error: "demo_read_only",
        message: "Process definitions are read-only in the public demo. " \
                 "Clone the repo to run a local instance: https://github.com/Chosen9115/opensop"
      }, status: :forbidden
    else
      flash[:alert] = "Process definitions are read-only in the public demo."
      redirect_back fallback_location: root_path, status: :see_other
    end
  end
end
