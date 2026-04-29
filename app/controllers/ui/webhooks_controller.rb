module Ui
  # GET /webhooks — list of recent inbound webhook callbacks.
  #
  # Backed by Sop::Callback, which currently models the three states defined
  # in the runtime: pending, received, expired. The page surfaces per-status
  # counts at the top, then a chronological list of callbacks, each linked to
  # the originating process instance.
  #
  # Eager-loads instance -> process to avoid N+1s when rendering rows.
  class WebhooksController < ApplicationController
    DEFAULT_LIMIT = 100

    def index
      @counts = Sop::Callback.group(:status).count
      @counts.default = 0

      @callbacks = Sop::Callback
                     .includes(instance: :process)
                     .order(created_at: :desc)
                     .limit(DEFAULT_LIMIT)

      @total = Sop::Callback.count
    end
  end
end
