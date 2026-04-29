module Ui
  # GET /templates — browseable list of starter process templates loaded from
  # `processes/**/*.sop.yaml`. File-driven (no DB). Each template offers a
  # "Use as base" action that, for now, links to the existing process detail
  # if a `Sop::Process` with the same name has already been imported, or
  # shows the YAML inline via a <details> disclosure.
  class TemplatesController < ApplicationController
    def index
      raw = Opensop::TemplateLoader.call

      imported_names = imported_template_names(raw)

      @templates = raw.map do |t|
        t.merge(existing_process: imported_names.include?(t[:name]))
      end
    end

    private

    # Returns a Set of template names that already exist as `Sop::Process`
    # records. Wrapped in a `rescue` so the page still renders on databases
    # that haven't been migrated (e.g. fresh checkouts running specs without
    # `rails db:prepare`).
    def imported_template_names(templates)
      names = templates.map { |t| t[:name] }.reject(&:blank?).uniq
      return Set.new if names.empty?

      Set.new(Sop::Process.where(name: names).pluck(:name))
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => e
      Rails.logger.warn("[Ui::TemplatesController] could not query Sop::Process: #{e.message}")
      Set.new
    end
  end
end
