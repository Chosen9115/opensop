require 'rails_helper'

RSpec.describe User, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:passkey_credentials).dependent(:destroy) }
    it { is_expected.to have_many(:auth_sessions).class_name("AuthSession").dependent(:destroy) }
    it { is_expected.to have_many(:magic_link_tokens).dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:user) }

    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_uniqueness_of(:email).case_insensitive }
    it { is_expected.to allow_value("user@example.com").for(:email) }
    it { is_expected.not_to allow_value("not-an-email").for(:email) }
    it { is_expected.not_to allow_value("no-at-sign.example.com").for(:email) }

    it { is_expected.to validate_length_of(:display_name).is_at_most(100).allow_blank }

    it { is_expected.to validate_inclusion_of(:role).in_array(User::ROLES) }
  end

  describe "email normalization" do
    it "downcases and strips whitespace before validation" do
      user = build(:user, email: "  Foo@EXAMPLE.com  ")
      user.valid?
      expect(user.email).to eq("foo@example.com")
    end

    it "leaves blank email alone (so presence validation triggers)" do
      user = build(:user, email: "")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it "treats emails as unique case-insensitively" do
      create(:user, email: "dup@example.com")
      duplicate = build(:user, email: "DUP@example.com")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:email]).to be_present
    end
  end

  describe "#admin?" do
    it "is true when role is admin" do
      expect(build(:user, role: "admin").admin?).to be true
    end
  end
end
