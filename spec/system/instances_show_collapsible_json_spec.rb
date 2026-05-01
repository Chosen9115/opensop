# frozen_string_literal: true

require "rails_helper"

# End-to-end system spec for the collapsible-JSON behavior on the instance
# show page. Drives a real headless Chrome to prove the <details>/<summary>
# toggle actually expands and collapses for users.
RSpec.describe "Instance show — collapsible JSON", type: :system do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  let!(:process) do
    create(:sop_process,
           name: "deploy-job",
           version: "1.0",
           status: "active",
           definition: {
             "opensop" => "0.1",
             "process" => { "name" => "deploy-job", "version" => "1.0", "steps" => [] }
           })
  end

  let!(:instance) do
    create(:sop_instance, :completed,
           process: process,
           process_name: "deploy-job",
           process_version: "1.0",
           inputs: {
             "company" => "Acme",
             "config" => { "tier" => "pro", "seats" => 5 }
           })
  end

  it "starts collapsed, expands on click, and collapses again on a second click" do
    visit ui_instance_path(instance)

    # Scalar value renders inline (no <details> wrapper) and is visible.
    expect(page).to have_text("Acme")

    summary = find("summary", text: "JSON object · 2 keys")

    # Collapsed by default — no <details> on the page has the `open` attribute,
    # and the JSON contents are not visible.
    expect(page).to have_css("details", count: 1)
    expect(page).to have_no_css("details[open]")
    expect(page).to have_no_text(%r{"tier": "pro"})

    # Click expands it: the <details> now carries `open` and the
    # pretty-printed JSON is visible.
    summary.click
    expect(page).to have_css("details[open]")
    expect(page).to have_text(%r{"tier": "pro"})
    expect(page).to have_text(%r{"seats": 5})

    # Click again collapses it: `open` is gone, JSON contents not visible.
    summary.click
    expect(page).to have_no_css("details[open]")
    expect(page).to have_no_text(%r{"tier": "pro"})
  end

end
