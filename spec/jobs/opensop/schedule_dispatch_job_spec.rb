require "rails_helper"

RSpec.describe Opensop::ScheduleDispatchJob do
  describe "#perform" do
    it "delegates to Opensop::ScheduleDispatcher and returns its result" do
      expected = Opensop::ScheduleDispatcher::Result.new(
        dispatched_count: 2,
        skipped_count: 1,
        failures: [ Opensop::ScheduleDispatcher::Failure.new(schedule_id: "abc", reason: "boom") ]
      )

      expect(Opensop::ScheduleDispatcher).to receive(:call).and_return(expected)

      result = described_class.new.perform

      expect(result).to be(expected)
      expect(result.dispatched_count).to eq(2)
      expect(result.skipped_count).to eq(1)
      expect(result.failures.size).to eq(1)
    end

    it "is enqueued on the :default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
