require 'rails_helper'

RSpec.describe Opensop::StepExecutors::Automated do
  let(:instance) { create(:sop_instance) }
  let(:step) { create(:sop_step, instance: instance, step_type: "automated", inputs: { "alpha" => 1 }) }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def write_script(name, body)
    path = File.join(@tmpdir, name)
    File.write(path, body)
    File.chmod(0o755, path)
    path
  end

  describe "#call" do
    it "parses a valid JSON stdout as outputs" do
      script = write_script("ok.rb", <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        input = JSON.parse(STDIN.read)
        puts JSON.dump({ "echo" => input, "verification_result" => "complete" })
      RUBY

      result = described_class.new.call(step, instance, { "run" => script })

      expect(result[:outputs]).to include("verification_result" => "complete")
      expect(result[:outputs]["echo"]).to eq({ "alpha" => 1 })
    end

    it "raises when the script does not exist" do
      expect {
        described_class.new.call(step, instance, { "run" => "/no/such/path/xyz-#{SecureRandom.hex(4)}.rb" })
      }.to raise_error(described_class::StepFailure, /script not found/)
    end

    it "raises when the script stdout is not JSON" do
      script = write_script("bad.rb", <<~RUBY)
        #!/usr/bin/env ruby
        puts "definitely not json"
      RUBY

      expect {
        described_class.new.call(step, instance, { "run" => script })
      }.to raise_error(described_class::StepFailure, /not valid JSON/)
    end

    it "raises when the JSON output is an array rather than an object" do
      script = write_script("arr.rb", <<~RUBY)
        #!/usr/bin/env ruby
        puts "[1,2,3]"
      RUBY

      expect {
        described_class.new.call(step, instance, { "run" => script })
      }.to raise_error(described_class::StepFailure, /JSON object/)
    end

    it "raises when `run:` is blank" do
      expect {
        described_class.new.call(step, instance, { "run" => "" })
      }.to raise_error(described_class::StepFailure, /missing `run:` path/)
    end
  end
end
