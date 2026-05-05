require "rails_helper"

RSpec.describe AuthEvent, type: :model do
  describe "validations" do
    it "is valid with a known kind and metadata default" do
      event = build(:auth_event)
      expect(event).to be_valid
    end

    it "rejects unknown kinds" do
      event = build(:auth_event, kind: "totally_made_up")
      expect(event).not_to be_valid
      expect(event.errors[:kind]).to be_present
    end

    it "requires kind to be present" do
      event = build(:auth_event, kind: nil)
      expect(event).not_to be_valid
      expect(event.errors[:kind]).to be_present
    end

    it "allows user to be nil" do
      event = build(:auth_event, user: nil, kind: "magic_link_requested")
      expect(event).to be_valid
    end

    it "accepts every kind in KINDS" do
      AuthEvent::KINDS.each do |k|
        event = build(:auth_event, kind: k)
        expect(event).to be_valid, "expected #{k} to be a valid kind"
      end
    end
  end

  describe "scopes" do
    let(:user) { create(:user) }

    describe ".recent" do
      it "orders by created_at desc" do
        older = create(:auth_event, user: user, created_at: 2.hours.ago)
        newer = create(:auth_event, user: user, created_at: 1.minute.ago)
        expect(AuthEvent.recent.to_a.first(2)).to eq([newer, older])
      end
    end

    describe ".for_user" do
      it "returns only the given user's events" do
        mine = create(:auth_event, user: user)
        _other = create(:auth_event)
        expect(AuthEvent.for_user(user)).to contain_exactly(mine)
      end
    end

    describe ".of_kind" do
      it "filters by kind" do
        signed_in = create(:auth_event, :signed_in, user: user)
        _signed_out = create(:auth_event, :signed_out, user: user)
        expect(AuthEvent.of_kind("signed_in")).to contain_exactly(signed_in)
      end
    end
  end
end
