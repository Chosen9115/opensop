require "rails_helper"
require "tmpdir"

RSpec.describe Opensop::StepExecutors::Loop do
  let(:instance) { create(:sop_instance) }
  let(:loop_step) do
    create(:sop_step,
           instance: instance,
           step_id: "process-each",
           step_type: "loop",
           inputs: {})
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  # Writes an executable Ruby script to the temp dir and returns its
  # absolute path. The script reads JSON from stdin and emits a JSON object
  # produced by `body_proc.call(parsed_input)`.
  def write_script(name, &body_proc)
    path = File.join(@tmpdir, name)
    # We serialize the body proc as inline Ruby — keep these tiny.
    raise ArgumentError, "block required" unless block_given?
    File.write(path, yield)
    File.chmod(0o755, path)
    path
  end

  def echo_value_script
    # An automated body step that returns { "value" => <input["value"]> }.
    write_script("echo_value.rb") do
      <<~RUBY
        #!/usr/bin/env ruby
        require "json"
        input = JSON.parse(STDIN.read)
        puts JSON.dump({ "value" => input["value"] })
      RUBY
    end
  end

  def double_value_script
    # Returns { "value" => 2 * input["value"] }.
    write_script("double_value.rb") do
      <<~RUBY
        #!/usr/bin/env ruby
        require "json"
        input = JSON.parse(STDIN.read)
        puts JSON.dump({ "value" => input["value"].to_i * 2 })
      RUBY
    end
  end

  def counter_script
    # Increments a counter file each call; returns { "count" => N, "done" => N>=3 }.
    counter_path = File.join(@tmpdir, "counter.txt")
    write_script("counter.rb") do
      <<~RUBY
        #!/usr/bin/env ruby
        require "json"
        path = #{counter_path.inspect}
        n = File.exist?(path) ? File.read(path).to_i : 0
        n += 1
        File.write(path, n.to_s)
        puts JSON.dump({ "count" => n, "done" => n >= 3 })
      RUBY
    end
  end

  def boom_script
    write_script("boom.rb") do
      <<~RUBY
        #!/usr/bin/env ruby
        STDERR.puts "kaboom"
        exit 2
      RUBY
    end
  end

  def configure_for_each_definition(script_path, aggregate: { "value" => "concat" })
    {
      "loop" => {
        "for_each"       => "process.inputs.items[*]",
        "as"             => "item",
        "max_iterations" => 1000,
        "aggregate"      => aggregate
      },
      "body" => [
        {
          "id"     => "echo",
          "type"   => "automated",
          "name"   => "Echo",
          "run"    => script_path,
          "inputs" => [
            { "name" => "value", "from" => "loop.item" }
          ]
        }
      ],
      "outputs" => [
        { "name" => "value", "type" => "object", "collection" => true }
      ]
    }
  end

  describe "#call — for_each" do
    it "iterates over a 3-item array and aggregates with concat" do
      instance.update!(inputs: { "items" => [ 1, 2, 3 ] })
      definition = configure_for_each_definition(echo_value_script)

      result = described_class.new.call(loop_step, instance, definition)

      expect(result[:outputs]["value"]).to eq([ 1, 2, 3 ])

      iterations = loop_step.iterations.ordered
      expect(iterations.size).to eq(3)
      expect(iterations.map(&:state)).to eq(%w[completed completed completed])
      expect(iterations.map { |it| it.iteration_inputs["item"] }).to eq([ 1, 2, 3 ])
      expect(iterations.map { |it| it.iteration_inputs["index"] }).to eq([ 0, 1, 2 ])
    end

    it "produces an empty result when the collection is empty" do
      instance.update!(inputs: { "items" => [] })
      definition = configure_for_each_definition(echo_value_script)

      result = described_class.new.call(loop_step, instance, definition)

      expect(result[:outputs]["value"]).to eq([])
      expect(loop_step.iterations.count).to eq(0)
    end

    it "raises StepFailure when for_each does not resolve to an array" do
      instance.update!(inputs: { "items" => { "not" => "an array" } })
      definition = configure_for_each_definition(echo_value_script).deep_dup
      # Drop the `[*]` selector so we get the executor's own type-check.
      definition["loop"]["for_each"] = "process.inputs.items"

      expect {
        described_class.new.call(loop_step, instance, definition)
      }.to raise_error(described_class::StepFailure, /did not resolve to an array/)
    end

    it "raises StepFailure when the reference itself is unresolvable" do
      instance.update!(inputs: { "items" => "not-an-array" })
      definition = configure_for_each_definition(echo_value_script)

      expect {
        described_class.new.call(loop_step, instance, definition)
      }.to raise_error(described_class::StepFailure, /could not resolve/)
    end

    it "supports aggregate: sum on numeric per-iteration values" do
      instance.update!(inputs: { "items" => [ 2, 3, 4 ] })
      definition = configure_for_each_definition(
        double_value_script,
        aggregate: { "value" => "sum" }
      )

      result = described_class.new.call(loop_step, instance, definition)

      expect(result[:outputs]["value"]).to eq(2*2 + 3*2 + 4*2)
    end

    it "raises StepFailure on aggregate: sum with non-numeric values" do
      instance.update!(inputs: { "items" => [ "a", "b" ] })
      definition = configure_for_each_definition(
        echo_value_script,
        aggregate: { "value" => "sum" }
      )

      expect {
        described_class.new.call(loop_step, instance, definition)
      }.to raise_error(described_class::StepFailure, /aggregate sum got non-numeric/)
    end

    it "supports aggregate: last to take only the final iteration's value" do
      instance.update!(inputs: { "items" => [ 10, 20, 30 ] })
      definition = configure_for_each_definition(
        echo_value_script,
        aggregate: { "value" => "last" }
      )

      result = described_class.new.call(loop_step, instance, definition)

      expect(result[:outputs]["value"]).to eq(30)
    end

    it "defaults missing aggregate rules to 'last'" do
      instance.update!(inputs: { "items" => [ 7, 8, 9 ] })
      definition = configure_for_each_definition(echo_value_script, aggregate: {})

      result = described_class.new.call(loop_step, instance, definition)

      expect(result[:outputs]["value"]).to eq(9)
    end

    it "fails-fast when a body step fails: marks iteration failed and re-raises" do
      instance.update!(inputs: { "items" => [ 1, 2, 3 ] })
      definition = configure_for_each_definition(boom_script)

      expect {
        described_class.new.call(loop_step, instance, definition)
      }.to raise_error(described_class::StepFailure, /iteration 0 failed at body step 'echo'/)

      iter = loop_step.iterations.ordered.first
      expect(iter.state_failed?).to be(true)
      expect(iter.error).to be_present

      body_step = instance.steps.where(parent_iteration_id: iter.id).first
      expect(body_step.state).to eq("failed")
      expect(body_step.error).to be_present
    end

    it "creates a Sop::StepIteration row per iteration with bound iter var" do
      instance.update!(inputs: { "items" => [ "x", "y" ] })
      definition = configure_for_each_definition(echo_value_script)

      described_class.new.call(loop_step, instance, definition)

      iterations = loop_step.iterations.ordered
      expect(iterations.pluck(:index)).to eq([ 0, 1 ])
      expect(iterations.first.iteration_inputs).to include("item" => "x", "index" => 0)
      expect(iterations.last.iteration_inputs).to include("item" => "y", "index" => 1)
    end
  end

  describe "#call — repeat_until" do
    it "terminates when the predicate is true at end of iteration" do
      definition = {
        "loop" => {
          "repeat_until"   => "outputs.done == true",
          "max_iterations" => 10,
          "aggregate"      => { "count" => "last" }
        },
        "body" => [
          {
            "id"     => "tick",
            "type"   => "automated",
            "name"   => "Tick",
            "run"    => counter_script,
            "inputs" => []
          }
        ],
        "outputs" => [
          { "name" => "count", "type" => "number" }
        ]
      }

      result = described_class.new.call(loop_step, instance, definition)

      expect(result[:outputs]["count"]).to eq(3)
      expect(loop_step.iterations.count).to eq(3)
    end

    it "raises StepFailure when max_iterations is hit" do
      definition = {
        "loop" => {
          "repeat_until"   => "outputs.done == true",
          "max_iterations" => 2,
          "aggregate"      => { "count" => "last" }
        },
        "body" => [
          {
            "id"     => "tick",
            "type"   => "automated",
            "name"   => "Tick",
            "run"    => counter_script,
            "inputs" => []
          }
        ],
        "outputs" => [
          { "name" => "count", "type" => "number" }
        ]
      }

      expect {
        described_class.new.call(loop_step, instance, definition)
      }.to raise_error(described_class::StepFailure, /max_iterations \(2\)/)
    end
  end

  describe "#call — while" do
    it "runs zero times when the predicate is false initially" do
      definition = {
        "loop" => {
          "while"          => "1 == 0",
          "max_iterations" => 5,
          "aggregate"      => {}
        },
        "body" => [
          {
            "id"     => "tick",
            "type"   => "automated",
            "name"   => "Tick",
            "run"    => counter_script,
            "inputs" => []
          }
        ],
        "outputs" => [
          { "name" => "count", "type" => "number" }
        ]
      }

      result = described_class.new.call(loop_step, instance, definition)

      expect(loop_step.iterations.count).to eq(0)
      expect(result[:outputs]["count"]).to be_nil
    end
  end
end
