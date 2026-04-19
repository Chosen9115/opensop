require 'rails_helper'

RSpec.describe Sop::Event, type: :model do
  describe "validations" do
    subject { build(:sop_event) }

    it { is_expected.to validate_presence_of(:event_type) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:instance).class_name("Sop::Instance").with_foreign_key(:instance_id) }
  end

  describe ".recent scope" do
    it "orders by created_at desc" do
      instance = create(:sop_instance)
      old = create(:sop_event, instance: instance, created_at: 2.hours.ago)
      newer = create(:sop_event, instance: instance, created_at: 1.minute.ago)

      expect(described_class.recent).to eq([ newer, old ])
    end
  end
end
