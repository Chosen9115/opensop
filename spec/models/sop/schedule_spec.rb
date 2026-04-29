require 'rails_helper'

RSpec.describe Sop::Schedule, type: :model do
  describe "validations" do
    subject { build(:sop_schedule) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:process_name) }
    it { is_expected.to validate_presence_of(:cron_expression) }

    describe "cron_expression parseability" do
      it "accepts a valid cron expression" do
        schedule = build(:sop_schedule, cron_expression: "0 9 * * *")
        expect(schedule).to be_valid
      end

      it "rejects an invalid cron expression" do
        schedule = build(:sop_schedule, cron_expression: "invalid")
        expect(schedule).not_to be_valid
        expect(schedule.errors[:cron_expression]).to be_present
      end
    end

    describe "timezone validation" do
      it "accepts a valid IANA timezone" do
        schedule = build(:sop_schedule, timezone: "UTC")
        expect(schedule).to be_valid
      end

      it "rejects an unknown timezone" do
        schedule = build(:sop_schedule, timezone: "NotAZone")
        expect(schedule).not_to be_valid
        expect(schedule.errors[:timezone]).to be_present
      end
    end

    describe "last_status inclusion" do
      it "allows nil" do
        schedule = build(:sop_schedule, last_status: nil)
        expect(schedule).to be_valid
      end

      it "allows 'success'" do
        schedule = build(:sop_schedule, last_status: "success")
        expect(schedule).to be_valid
      end

      it "allows 'failed'" do
        schedule = build(:sop_schedule, last_status: "failed")
        expect(schedule).to be_valid
      end

      it "rejects an unknown status" do
        schedule = build(:sop_schedule, last_status: "weird")
        expect(schedule).not_to be_valid
        expect(schedule.errors[:last_status]).to be_present
      end
    end
  end

  describe "scopes" do
    describe ".enabled" do
      it "returns only enabled schedules" do
        on  = create(:sop_schedule, enabled: true)
        create(:sop_schedule, enabled: false)
        expect(described_class.enabled).to contain_exactly(on)
      end
    end

    describe ".due" do
      it "includes schedules whose next_run_at is in the past" do
        due_one = create(:sop_schedule, enabled: true, next_run_at: 1.minute.ago)
        expect(described_class.due).to include(due_one)
      end

      it "excludes schedules whose next_run_at is in the future" do
        future = create(:sop_schedule, enabled: true, next_run_at: 10.minutes.from_now)
        expect(described_class.due).not_to include(future)
      end

      it "excludes disabled schedules even if their next_run_at is in the past" do
        disabled = create(:sop_schedule, enabled: false, next_run_at: 1.minute.ago)
        expect(described_class.due).not_to include(disabled)
      end
    end
  end

  describe "#compute_next_run_at" do
    it "returns a Time in the future" do
      schedule = build(:sop_schedule, cron_expression: "0 9 * * *", timezone: "UTC")
      result = schedule.compute_next_run_at(from: Time.utc(2026, 4, 29, 8, 0, 0))
      expect(result).to be_a(Time)
      expect(result).to be > Time.utc(2026, 4, 29, 8, 0, 0)
    end

    it "returns a UTC time" do
      schedule = build(:sop_schedule, cron_expression: "0 9 * * *", timezone: "America/New_York")
      result = schedule.compute_next_run_at
      expect(result).to be_a(Time)
      expect(result.utc?).to be true
    end
  end

  describe "#due?" do
    it "is true when enabled and next_run_at is in the past" do
      schedule = build(:sop_schedule, enabled: true, next_run_at: 1.minute.ago)
      expect(schedule.due?).to be true
    end

    it "is false when disabled" do
      schedule = build(:sop_schedule, enabled: false, next_run_at: 1.minute.ago)
      expect(schedule.due?).to be false
    end

    it "is false when next_run_at is in the future" do
      schedule = build(:sop_schedule, enabled: true, next_run_at: 10.minutes.from_now)
      expect(schedule.due?).to be false
    end

    it "is false when next_run_at is nil" do
      schedule = build(:sop_schedule, enabled: true, next_run_at: nil)
      expect(schedule.due?).to be false
    end
  end

  describe "before_validation :set_next_run_at_if_blank" do
    it "populates next_run_at when blank on create" do
      schedule = build(:sop_schedule, next_run_at: nil)
      schedule.valid?
      expect(schedule.next_run_at).to be_present
      expect(schedule.next_run_at).to be_a(Time)
    end

    it "does not overwrite an existing next_run_at" do
      explicit = 1.day.from_now.change(usec: 0)
      schedule = build(:sop_schedule, next_run_at: explicit)
      schedule.valid?
      expect(schedule.next_run_at).to be_within(1.second).of(explicit)
    end
  end

  describe "factory" do
    it "is valid" do
      expect(build(:sop_schedule)).to be_valid
    end
  end
end
