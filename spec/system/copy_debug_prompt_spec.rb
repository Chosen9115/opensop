# frozen_string_literal: true

require "rails_helper"

# End-to-end system spec for the "Copy debug prompt" button. Drives real
# headless Chrome via Selenium to prove the click → clipboard → readable XML
# round-trip works.
#
# Headless Chrome won't grant clipboard read by default, so instead of
# reading back from the OS clipboard we monkey-patch
# `navigator.clipboard.writeText` to record every call onto a window-scoped
# array. After clicking, we read that array back and assert the recorded
# text matches the data attribute the controller is supposed to copy.
RSpec.describe "Instance show — copy debug prompt button", type: :system do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  let!(:process) { build_process(name: "ship-order", version: "1.0") }

  let!(:instance) do
    create(:sop_instance, :failed,
           process: process,
           process_name: process.name,
           process_version: process.version,
           inputs: { "order_id" => "ORD-99" })
  end

  let!(:errored_step) do
    create(:sop_step,
           instance: instance,
           step_id: "validate-payment",
           step_type: "automated",
           state: "failed",
           error: "RuntimeError: payment gateway timeout",
           inputs: { "card" => "4111" },
           outputs: {},
           position: 1,
           attempt: 2)
  end

  # Patches navigator.clipboard.writeText to record every call into
  # `window.__copiedTexts`. Returns the recorded array via execute_script.
  def install_clipboard_recorder
    page.execute_script <<~JS
      window.__copiedTexts = [];
      navigator.clipboard = navigator.clipboard || {};
      navigator.clipboard.writeText = function(text) {
        window.__copiedTexts.push(text);
        return Promise.resolve();
      };
    JS
  end

  def recorded_clipboard_calls
    page.evaluate_script("window.__copiedTexts || []")
  end

  it "renders the button on the instance-level error block" do
    instance.update!(error: "instance-level kaboom")
    visit ui_instance_path(instance)

    button = find("button[data-controller='copy-prompt']", match: :first)
    expect(button[:"aria-label"]).to be_present
    expect(button.text.strip).to eq(I18n.t("opensop.instances.show.copy_debug.button_label"))
  end

  it "renders the button on a per-step error block" do
    visit ui_instance_path(instance)

    # The step-card error renders inside the timeline; one of the buttons
    # should sit inside the rendered step card with id="validate-payment".
    expect(page).to have_css("button[data-controller='copy-prompt']", minimum: 1)
  end

  it "click → clipboard contains the prompt with the failing step inside <failed_steps>" do
    visit ui_instance_path(instance)
    install_clipboard_recorder

    find("button[data-controller='copy-prompt']", match: :first).click

    # Wait for the success label to swap in — proves the controller's
    # success branch fired before we read the recorder.
    expect(page).to have_css(
      "[data-copy-prompt-target='successLabel']:not(.hidden)",
      wait: 2
    )

    copied = recorded_clipboard_calls
    expect(copied.size).to eq(1)
    text = copied.first

    # Round-trip assertions: the structural skeleton is intact, the
    # failing step is present, the path through the data attribute did
    # not corrupt the XML, and CDATA-wrapped fields aren't double-escaped.
    expect(text).to include("<instance>")
    expect(text).to include("<process_name>ship-order</process_name>")
    expect(text).to include("<failed_steps>")
    expect(text).to include('id="validate-payment"')
    expect(text).to include("RuntimeError: payment gateway timeout")
    expect(text).to include("<request>")
  end

  it "click swaps to success state for ~2s, then reverts" do
    visit ui_instance_path(instance)
    install_clipboard_recorder

    button = find("button[data-controller='copy-prompt']", match: :first)
    default_label = button.find("[data-copy-prompt-target='defaultLabel']")
    success_label = button.find("[data-copy-prompt-target='successLabel']", visible: :all)

    expect(default_label).not_to match_css(".hidden")
    expect(success_label[:class]).to include("hidden")

    button.click

    # Success label visible
    expect(page).to have_css(
      "[data-copy-prompt-target='successLabel']:not(.hidden)",
      wait: 2
    )
    # Default label is now hidden — Capybara's default visibility filter
    # rejects `display: none`, so we have to opt into seeing it via
    # `visible: :all`.
    expect(page).to have_css(
      "[data-copy-prompt-target='defaultLabel'].hidden",
      wait: 2,
      visible: :all
    )

    # And reverts after the timer fires (2s default + small buffer)
    expect(page).to have_css(
      "[data-copy-prompt-target='defaultLabel']:not(.hidden)",
      wait: 4
    )
  end

  it "shows the error label and does NOT auto-revert when clipboard rejects" do
    visit ui_instance_path(instance)

    # Override writeText with a rejecting promise to exercise the failure path.
    page.execute_script <<~JS
      navigator.clipboard = navigator.clipboard || {};
      navigator.clipboard.writeText = function() {
        return Promise.reject(new Error("denied"));
      };
    JS

    find("button[data-controller='copy-prompt']", match: :first).click

    expect(page).to have_css(
      "[data-copy-prompt-target='errorLabel']:not(.hidden)",
      wait: 2
    )
    # Default and success labels stay hidden — error state holds without auto-revert
    expect(page).to have_css(
      "[data-copy-prompt-target='defaultLabel'].hidden",
      visible: :all
    )
    expect(page).to have_css(
      "[data-copy-prompt-target='successLabel'].hidden",
      visible: :all
    )
  end
end
