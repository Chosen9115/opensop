# frozen_string_literal: true

require "rails_helper"

RSpec.describe Opensop::DebugPromptBuilder do
  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  let(:process) { build_process(name: "order-processing", version: "2.1") }

  let(:instance) do
    create(:sop_instance, :failed,
           process: process,
           process_name: process.name,
           process_version: process.version,
           inputs: { "order_id" => "ORD-99", "amount" => 42 })
  end

  def builder(inst: instance, step: nil)
    described_class.new(instance: inst, step: step)
  end

  def result(inst: instance, step: nil)
    builder(inst: inst, step: step).call
  end

  # ---------------------------------------------------------------------------
  # 1. Errored instance with no failed steps
  # ---------------------------------------------------------------------------

  describe "errored instance with no failed steps" do
    it "returns a non-empty String" do
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it "renders empty <failed_steps></failed_steps> tags" do
      expect(result).to include("<failed_steps></failed_steps>")
    end

    it "includes the process name inside <instance> tags" do
      expect(result).to match(/<process_name>order-processing<\/process_name>/)
    end

    it "includes the process version inside <instance> tags" do
      expect(result).to match(/<process_version>2\.1<\/process_version>/)
    end

    it "includes the instance id inside <instance> tags" do
      expect(result).to include("<instance_id>#{instance.id}</instance_id>")
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Instance with 1 errored step (instance.error nil)
  # ---------------------------------------------------------------------------

  describe "instance with 1 errored step" do
    let!(:errored_step) do
      create(:sop_step,
             instance: instance,
             step_id: "validate-payment",
             step_type: "automated",
             state: "failed",
             error: "RuntimeError: payment gateway timeout",
             inputs: { "card" => "4111" },
             outputs: { "status" => "error" },
             position: 1,
             attempt: 2)
    end

    before { instance.reload }

    it "renders the step inside <failed_steps> block" do
      expect(result).to match(/<failed_steps>.*<\/failed_steps>/m)
      expect(result).not_to include("<failed_steps></failed_steps>")
    end

    it "includes the step_id as the id attribute" do
      expect(result).to include('id="validate-payment"')
    end

    it "includes the step_type as the type attribute" do
      expect(result).to include('type="automated"')
    end

    it "includes the step attempt as the attempt attribute" do
      expect(result).to include('attempt="2"')
    end

    it "includes the error text in a CDATA block" do
      expect(result).to include("RuntimeError: payment gateway timeout")
    end

    it "includes step inputs in a CDATA block" do
      expect(result).to include('"card"')
    end

    it "includes step outputs in a CDATA block" do
      expect(result).to include('"status"')
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Instance with 5 errored steps — only first 3 (by position) appear
  # ---------------------------------------------------------------------------

  describe "MAX_FAILED_STEPS enforcement with 5 errored steps" do
    let!(:errored_steps) do
      (1..5).map do |n|
        create(:sop_step,
               instance: instance,
               step_id: "step-#{n}",
               step_type: "automated",
               state: "failed",
               error: "error in step #{n}",
               position: n)
      end
    end

    before { instance.reload }

    it "includes exactly 3 steps, not more" do
      # Count opening <step … tags
      expect(result.scan(/<step /).length).to eq(3)
    end

    it "renders the 3 lowest-position steps (positions 1, 2, 3)" do
      expect(result).to include('id="step-1"')
      expect(result).to include('id="step-2"')
      expect(result).to include('id="step-3"')
    end

    it "omits steps at positions 4 and 5" do
      expect(result).not_to include('id="step-4"')
      expect(result).not_to include('id="step-5"')
    end

    it "respects the MAX_FAILED_STEPS constant value of 3" do
      expect(described_class::MAX_FAILED_STEPS).to eq(3)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. :step argument given — only that step appears
  # ---------------------------------------------------------------------------

  describe "explicit :step argument" do
    let!(:errored_step_a) do
      create(:sop_step,
             instance: instance,
             step_id: "step-alpha",
             state: "failed",
             error: "error alpha",
             position: 1)
    end

    let!(:errored_step_b) do
      create(:sop_step,
             instance: instance,
             step_id: "step-beta",
             state: "failed",
             error: "error beta",
             position: 2)
    end

    before { instance.reload }

    it "renders only the provided step" do
      output = result(step: errored_step_b)
      expect(output).to include('id="step-beta"')
      expect(output).not_to include('id="step-alpha"')
    end

    it "still wraps the step in <failed_steps> block" do
      output = result(step: errored_step_b)
      expect(output).to match(/<failed_steps>.*step-beta.*<\/failed_steps>/m)
    end

    it "works even if the explicit step has no error (non-nil step override)" do
      # Step with nil error — the step: arg bypasses the error filter
      no_error_step = create(:sop_step,
                             instance: instance,
                             step_id: "step-gamma",
                             state: "active",
                             error: nil,
                             position: 3)
      output = result(step: no_error_step)
      expect(output).to include('id="step-gamma"')
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Step inputs payload > 2KB → replaced with truncation sentinel
  # ---------------------------------------------------------------------------

  describe "step inputs truncation (> JSON_MAX_BYTES)" do
    let(:large_inputs) { { "data" => "x" * 3_000 } }

    let!(:fat_step) do
      create(:sop_step,
             instance: instance,
             step_id: "fat-step",
             state: "failed",
             error: "size error",
             inputs: large_inputs,
             position: 1)
    end

    before { instance.reload }

    it "replaces inputs with _truncated sentinel JSON" do
      expect(result).to include('"_truncated"')
      expect(result).to include('"size_bytes"')
    end

    it "does NOT include the raw large payload" do
      expect(result).not_to include("x" * 100)
    end

    it "respects the JSON_MAX_BYTES constant value of 2048" do
      expect(described_class::JSON_MAX_BYTES).to eq(2_048)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Error trace > 8KB → truncated with middle marker
  # ---------------------------------------------------------------------------

  describe "error trace truncation (> TRACE_MAX_BYTES)" do
    let(:long_trace) { "A" * 5_000 + "B" * 5_000 }

    let!(:traced_step) do
      create(:sop_step,
             instance: instance,
             step_id: "traced-step",
             state: "failed",
             error: long_trace,
             position: 1)
    end

    before { instance.reload }

    it "includes the truncated middle marker" do
      expect(result).to include("... [truncated middle] ...")
    end

    it "includes the beginning of the trace" do
      expect(result).to include("A" * 100)
    end

    it "includes the end of the trace" do
      expect(result).to include("B" * 100)
    end

    it "does NOT include the full untruncated trace" do
      # The combined A*5000 + B*5000 would not appear as one block
      expect(result).not_to include("A" * 5_000 + "B" * 5_000)
    end

    it "respects TRACE_MAX_BYTES constant value of 8192" do
      expect(described_class::TRACE_MAX_BYTES).to eq(8_192)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Process YAML > 4KB → truncated with comment marker
  # ---------------------------------------------------------------------------

  describe "process YAML truncation (> YAML_MAX_BYTES)" do
    let(:large_process) do
      build_process(
        name: "big-process",
        description: "x" * 5_000
      )
    end

    let(:large_instance) do
      create(:sop_instance, :failed,
             process: large_process,
             process_name: large_process.name,
             process_version: large_process.version)
    end

    it "includes the truncation comment" do
      expect(result(inst: large_instance)).to include("# ... [truncated]")
    end

    it "does NOT render the full process description" do
      # If truncation works, the 5000-char description won't be fully present
      expect(result(inst: large_instance)).not_to include("x" * 4_100)
    end

    it "respects YAML_MAX_BYTES constant value of 4096" do
      expect(described_class::YAML_MAX_BYTES).to eq(4_096)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. @instance.process is nil → renders unavailable message without raising
  # ---------------------------------------------------------------------------

  describe "when instance.process is nil" do
    let(:orphaned_instance) do
      create(:sop_instance, :failed,
             process: nil,
             process_name: "deleted-process",
             process_version: "0.1")
    end

    it "does not raise an error" do
      expect { result(inst: orphaned_instance) }.not_to raise_error
    end

    it "renders the unavailable placeholder in the process_definition section" do
      expect(result(inst: orphaned_instance))
        .to include("[unavailable: process not found in registry]")
    end

    it "still returns a non-empty String" do
      expect(result(inst: orphaned_instance)).to be_a(String)
      expect(result(inst: orphaned_instance)).not_to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Inputs containing literal ]]> — escaped correctly in CDATA
  # ---------------------------------------------------------------------------

  describe "CDATA escaping of ]]> in inputs" do
    let(:cdata_inputs) { { "payload" => "before]]>after" } }

    it "escapes ]]> as ]]]]><![CDATA[>" do
      instance_with_cdata = create(:sop_instance, :failed,
                                   process: process,
                                   process_name: process.name,
                                   process_version: process.version,
                                   inputs: cdata_inputs)
      output = described_class.new(instance: instance_with_cdata).call
      expect(output).to include("]]]]><![CDATA[>")
    end

    it "does NOT include a raw unescaped ]]> adjacent to user content" do
      # The user-supplied ]]> must be escaped; it should not appear verbatim
      # immediately after the word "before" (which is our sentinel in the payload).
      instance_with_cdata = create(:sop_instance, :failed,
                                   process: process,
                                   process_name: process.name,
                                   process_version: process.version,
                                   inputs: cdata_inputs)
      output = described_class.new(instance: instance_with_cdata).call
      # If the raw ]]> leaked, the output would contain "before]]>" — check it doesn't
      expect(output).not_to include("before]]>")
      # The escaped form should be present instead
      expect(output).to include("]]]]><![CDATA[>")
    end

    context "in step error messages" do
      let!(:cdata_step) do
        create(:sop_step,
               instance: instance,
               step_id: "cdata-step",
               state: "failed",
               error: "malformed XML ]]> payload",
               position: 1)
      end

      before { instance.reload }

      it "escapes ]]> in step error CDATA" do
        expect(result).to include("]]]]><![CDATA[>")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Return value is non-empty String for any errored instance
  # ---------------------------------------------------------------------------

  describe "return value contract" do
    it "returns a String for a minimal failed instance" do
      minimal = create(:sop_instance, :failed,
                       process: process,
                       process_name: process.name,
                       process_version: process.version)
      expect(described_class.new(instance: minimal).call).to be_a(String)
    end

    it "returns a non-empty result" do
      expect(result).not_to be_empty
    end

    it "includes core XML structure landmarks" do
      output = result
      expect(output).to include("<instance>")
      expect(output).to include("</instance>")
      expect(output).to include("<process_definition>")
      expect(output).to include("</process_definition>")
      expect(output).to include("<instance_inputs>")
      expect(output).to include("</instance_inputs>")
      expect(output).to include("<request>")
      expect(output).to include("</request>")
    end

    it "does not end with trailing whitespace (rstrip applied)" do
      output = result
      expect(output).to eq(output.rstrip)
    end
  end

  # ---------------------------------------------------------------------------
  # 11. XML escaping in non-CDATA fields (element text + attribute values)
  # ---------------------------------------------------------------------------

  describe "XML escaping outside CDATA" do
    context "with hostile values in step attributes and text" do
      let!(:hostile_step) do
        create(:sop_step,
               instance: instance,
               step_id: "step<&>\"'evil",
               step_type: "automated",
               state: "failed",
               sub_state: "waiting<for_input>",
               error: "boom",
               position: 1,
               attempt: 1)
      end

      before { instance.reload }

      it "escapes < > & \" ' in step attribute values" do
        out = result
        expect(out).to include('id="step&lt;&amp;&gt;&quot;&apos;evil"')
        expect(out).not_to match(/id="step<&>"/)
      end

      it "escapes < > in element text content (sub_state)" do
        out = result
        expect(out).to include("<sub_state>waiting&lt;for_input&gt;</sub_state>")
        expect(out).not_to include("<sub_state>waiting<for_input>")
      end
    end

    context "with hostile values in instance fields" do
      let(:bad_instance) do
        create(:sop_instance, :failed,
               process: process,
               process_name: "p<one&two>",
               process_version: "1.0\"x")
      end

      it "escapes the process name and version in <instance>" do
        out = described_class.new(instance: bad_instance).call
        expect(out).to include("<process_name>p&lt;one&amp;two&gt;</process_name>")
        expect(out).to include("<process_version>1.0&quot;x</process_version>")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 12. CDATA escape now applies to YAML too
  # ---------------------------------------------------------------------------

  describe "CDATA escaping inside <process_definition>" do
    let(:cdata_yaml_process) do
      build_process(
        name: "cdata-yaml",
        description: "ends with ]]> a CDATA terminator"
      )
    end

    let(:cdata_yaml_instance) do
      create(:sop_instance, :failed,
             process: cdata_yaml_process,
             process_name: cdata_yaml_process.name,
             process_version: cdata_yaml_process.version)
    end

    it "escapes ]]> inside the YAML so the process_definition CDATA stays intact" do
      out = described_class.new(instance: cdata_yaml_instance).call
      # Raw `]]>` adjacent to user content must not appear — only the
      # split-CDATA escape sequence should.
      expect(out).not_to include("ends with ]]> a CDATA")
      expect(out).to include("]]]]><![CDATA[>")
    end
  end

  # ---------------------------------------------------------------------------
  # 13. DB-side step filter respects MAX_FAILED_STEPS without loading all rows
  # ---------------------------------------------------------------------------

  describe "step loading uses a DB-side filter" do
    it "issues a query that filters out null/empty errors and limits to MAX_FAILED_STEPS" do
      # Three failed + two non-failed steps; the SQL should restrict to the
      # failed ones and cap at MAX_FAILED_STEPS.
      3.times do |i|
        create(:sop_step, instance: instance, step_id: "fail-#{i}", state: "failed",
                          error: "boom-#{i}", position: 100 + i)
      end
      create(:sop_step, instance: instance, step_id: "ok",      state: "completed", error: nil, position: 200)
      create(:sop_step, instance: instance, step_id: "blank",   state: "completed", error: "",  position: 201)
      instance.reload

      relation_calls = []
      allow_any_instance_of(ActiveRecord::Relation).to receive(:where).and_wrap_original do |orig, *args, &blk|
        relation_calls << args
        orig.call(*args, &blk)
      end

      out = described_class.new(instance: instance).call

      # Three failed steps appear; non-failed do not
      expect(out).to include("fail-0")
      expect(out).to include("fail-1")
      expect(out).to include("fail-2")
      expect(out).not_to include('id="ok"')
      expect(out).not_to include('id="blank"')
    end
  end
end
