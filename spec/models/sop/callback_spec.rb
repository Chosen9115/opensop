require 'rails_helper'

RSpec.describe Sop::Callback, type: :model do
  describe "validations" do
    subject { build(:sop_callback) }

    it { is_expected.to validate_presence_of(:step_id) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:instance).class_name("Sop::Instance").with_foreign_key(:instance_id) }
  end

  describe "#generate_callback_path" do
    it "auto-generates a /sop/webhooks/<uuid> path before validation" do
      callback = build(:sop_callback, callback_path: nil)
      callback.valid?
      expect(callback.callback_path).to match(%r{\A/sop/webhooks/[0-9a-f-]{36}\z})
    end

    it "does not overwrite an explicitly supplied callback_path" do
      callback = build(:sop_callback, callback_path: "/sop/webhooks/custom-123")
      callback.valid?
      expect(callback.callback_path).to eq("/sop/webhooks/custom-123")
    end
  end

  describe "callback_path uniqueness" do
    it "rejects duplicates at the DB level" do
      first = create(:sop_callback)
      dup = build(:sop_callback, callback_path: first.callback_path, instance: first.instance)
      expect(dup).not_to be_valid
      expect(dup.errors[:callback_path]).to be_present
    end
  end
end
