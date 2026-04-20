# frozen_string_literal: true

namespace :opensop do
  desc "Load all .sop.yaml process definitions under processes/ into the registry"
  task load_processes: :environment do
    results = Opensop::Registry.load_all
    if results.empty?
      puts "No .sop.yaml files found under #{Rails.root.join("processes")} (the engine recursively loads all subdirectories, e.g. processes/examples/, processes/<your-org>/)."
    else
      puts "Loaded #{results.size} process definition(s):"
      results.each do |record|
        puts "  - #{record.name} v#{record.version} (status: #{record.status})"
      end
    end
  end

  desc "Run the customer-onboarding process end-to-end as a demo"
  task demo: :environment do
    demo = OpensopDemo.new
    demo.run_customer_onboarding!
  end

  desc "Run the lead-qualification process end-to-end as a demo"
  task demo_leads: :environment do
    demo = OpensopDemo.new
    demo.run_lead_qualification!
  end
end

# ---------------------------------------------------------------------------
# OpenSOP demo runner
#
# A thin wrapper that drives two processes end-to-end through the real
# Opensop::InstanceExecutor, printing state after each transition. The
# executor does all the real work; this script only plays the "human"
# and "third party" roles by calling the same public entry points the
# controllers would.
# ---------------------------------------------------------------------------
class OpensopDemo
  class DemoFailure < StandardError; end

  SECTION = "=" * 72
  SUBSECTION = "-" * 72

  def run_customer_onboarding!
    puts SECTION
    puts "opensop:demo  —  customer-onboarding end-to-end"
    puts SECTION

    clean_demo_data!
    load_processes!

    process = Sop::Process.active.find_by!(name: "customer-onboarding")

    instance = Opensop::InstanceExecutor.start(
      process: process,
      inputs: {
        "company_name"  => "Acme Logistics",
        "contact_email" => "ops@example.com",
        "country"       => "MX",
        "source_channel" => "referral",
        "deal_id"       => "CRM-9912"
      },
      metadata: { "demo" => true, "company_name" => "Acme Logistics" }
    )

    puts_state(instance, title: "After start (should pause at collect-business-info)")
    expect!(instance.state == "running", "instance should be running after start, got #{instance.state.inspect}")
    expect_step!(instance, "collect-business-info", state: "active", sub_state: "waiting_for_input")

    # --- Step 1: submit the form --------------------------------------------
    puts SUBSECTION
    puts "-> Submitting form step `collect-business-info`"
    business_record = {
      "legal_name"      => "Acme Logistics, Inc.",
      "rfc"             => "ACM060402AA1",
      "fiscal_address"  => "1 Example Way, Anytown, MX",
      "industry"        => "logistics",
      "annual_revenue"  => 48_000_000
    }

    Opensop::InstanceExecutor.submit_step(
      instance: instance,
      step_id: "collect-business-info",
      outputs: { "business_record" => business_record },
      decided_by: "human:demo"
    )

    puts_state(instance, title: "After form submit (verify-documents should have run)")
    expect_step!(instance, "collect-business-info", state: "completed")
    expect_step!(instance, "verify-documents", state: "completed")
    vr = instance.steps.find_by(step_id: "verify-documents").outputs["verification_result"]
    expect!(vr == "complete", "verify-documents verification_result should be 'complete', got #{vr.inspect}")
    expect_step!(instance, "review-application", state: "active", sub_state: "escalated")

    # --- Step 3: submit the judgment ----------------------------------------
    puts SUBSECTION
    puts "-> Submitting judgment step `review-application` as approve"

    Opensop::InstanceExecutor.submit_step(
      instance: instance,
      step_id: "review-application",
      outputs: {
        "decision"    => "approve",
        "risk_notes"  => "Established company with 12yr history"
      },
      decided_by: "human:demo"
    )

    puts_state(instance, title: "After judgment approve (webhook should be waiting)")
    expect_step!(instance, "review-application", state: "completed")
    expect_step!(instance, "submit-to-compliance", state: "active", sub_state: "waiting_for_callback")

    # --- Step 4: simulate the compliance callback ---------------------------
    puts SUBSECTION
    puts "-> Simulating compliance provider callback"

    callback = instance.callbacks.find_by!(step_id: "submit-to-compliance", status: "pending")
    puts "   callback_path = #{callback.callback_path}"

    payload = { "entity_id" => "mnx_442", "compliance_status" => "approved" }
    simulate_webhook_callback!(instance, callback, payload)

    puts_state(instance, title: "After compliance callback (should advance through the rest)")

    expect_step!(instance, "submit-to-compliance", state: "completed")
    expect_step!(instance, "create-account", state: "completed")
    expect_step!(instance, "send-welcome", state: "completed")
    expect!(instance.state == "completed",
            "instance should be completed, got #{instance.state.inspect} (error=#{instance.error.inspect})")

    outs = instance.outputs || {}
    expect!(outs["account_id"].to_s.start_with?("acct_"),
            "expected account_id like acct_*, got #{outs["account_id"].inspect}")
    expect!(outs["member_id"].to_s.start_with?("mem_"),
            "expected member_id like mem_*, got #{outs["member_id"].inspect}")
    expect!(outs["status"].to_s == "approved" || outs["status"].nil?,
            "status output should be 'approved' or nil (no explicit mapping), got #{outs["status"].inspect}")

    puts SECTION
    puts "demo OK — instance #{instance.id} completed"
    puts "outputs: #{outs.inspect}"
    puts SECTION
  rescue DemoFailure => e
    warn "DEMO FAILED: #{e.message}"
    exit 1
  rescue StandardError => e
    warn "DEMO CRASHED: #{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n")
    exit 1
  end

  def run_lead_qualification!
    puts SECTION
    puts "opensop:demo_leads  —  lead-qualification end-to-end"
    puts SECTION

    clean_demo_data!
    load_processes!

    process = Sop::Process.active.find_by!(name: "lead-qualification")

    instance = Opensop::InstanceExecutor.start(
      process: process,
      inputs: {
        "lead_name"  => "Ana García",
        "lead_email" => "ana@example.com",
        "source"     => "website"
      },
      metadata: { "demo" => true, "lead_name" => "Ana García" }
    )

    puts_state(instance, title: "After start (should pause at collect-context)")
    expect_step!(instance, "collect-context", state: "active", sub_state: "waiting_for_input")

    puts SUBSECTION
    puts "-> Submitting form step `collect-context`"

    Opensop::InstanceExecutor.submit_step(
      instance: instance,
      step_id: "collect-context",
      outputs: {
        "budget"   => 12_000,
        "timeline" => "immediate",
        "notes"    => "Has active RFP out, wants to decide this quarter"
      },
      decided_by: "human:demo"
    )

    puts_state(instance, title: "After form submit (scoring + notify should have run)")
    expect_step!(instance, "score-lead", state: "completed")
    expect_step!(instance, "notify-team", state: "completed")
    expect!(instance.state == "completed",
            "instance should be completed, got #{instance.state.inspect} (error=#{instance.error.inspect})")

    outs = instance.outputs || {}
    expect!(outs["score"].is_a?(Numeric), "score should be numeric, got #{outs["score"].inspect}")
    expect!(outs.key?("qualified"), "qualified output missing")

    puts SECTION
    puts "demo_leads OK — instance #{instance.id} completed"
    puts "outputs: #{outs.inspect}"
    puts SECTION
  rescue DemoFailure => e
    warn "DEMO FAILED: #{e.message}"
    exit 1
  rescue StandardError => e
    warn "DEMO CRASHED: #{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n")
    exit 1
  end

  # -------------------------------------------------------------------------
  # helpers
  # -------------------------------------------------------------------------

  def clean_demo_data!
    demo_instances = Sop::Instance.where("metadata ->> 'demo' = ?", "true")
    ids = demo_instances.pluck(:id)
    if ids.any?
      Sop::Event.where(instance_id: ids).delete_all
      Sop::Step.where(instance_id: ids).delete_all
      Sop::Callback.where(instance_id: ids).delete_all
      Sop::Instance.where(id: ids).delete_all
      puts "cleaned #{ids.size} prior demo instance(s)"
    end
  end

  def load_processes!
    Opensop::Registry.load_all
  end

  def puts_state(instance, title:)
    instance.reload
    puts SUBSECTION
    puts title
    puts "  instance ##{instance.id} [#{instance.state}]  process=#{instance.process_name}@#{instance.process_version}"
    instance.steps.ordered.each do |step|
      badge = step.sub_state ? "#{step.state}/#{step.sub_state}" : step.state
      out_preview = step.outputs.present? ? step.outputs.to_json[0, 80] : "-"
      puts "    #{step.position.to_s.rjust(2)}. #{step.step_id.ljust(24)} [#{badge}]  #{out_preview}"
    end
    if instance.completed? && instance.outputs.present?
      puts "  outputs: #{instance.outputs.to_json}"
    end
  end

  def simulate_webhook_callback!(instance, callback, payload)
    # Mirror the logic of Sop::WebhooksController#receive without going
    # through HTTP. See app/controllers/sop/webhooks_controller.rb.
    ActiveRecord::Base.transaction do
      callback.update!(response: payload, status: "received")
    end
    step = instance.steps.find_by!(step_id: callback.step_id)
    merged_outputs = (step.outputs || {}).merge(payload).merge("webhook_response" => payload)
    Opensop::InstanceExecutor.submit_step(
      instance: instance,
      step_id: step.step_id,
      outputs: merged_outputs,
      decided_by: "webhook"
    )
  end

  def expect!(condition, message)
    raise DemoFailure, message unless condition
  end

  def expect_step!(instance, step_id, state:, sub_state: :__unset)
    step = instance.steps.find_by(step_id: step_id)
    raise DemoFailure, "step #{step_id.inspect} not found on instance #{instance.id}" unless step

    unless step.state == state
      raise DemoFailure,
            "step #{step_id.inspect} expected state=#{state.inspect}, got #{step.state.inspect} (sub_state=#{step.sub_state.inspect}, error=#{step.error.inspect})"
    end
    return if sub_state == :__unset

    unless step.sub_state == sub_state
      raise DemoFailure,
            "step #{step_id.inspect} expected sub_state=#{sub_state.inspect}, got #{step.sub_state.inspect}"
    end
  end
end
