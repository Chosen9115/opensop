require 'rails_helper'

RSpec.describe PasskeyCredential, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject { build(:passkey_credential) }

    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_uniqueness_of(:external_id) }
    it { is_expected.to validate_presence_of(:public_key) }
    it { is_expected.to validate_presence_of(:nickname) }
    it { is_expected.to validate_length_of(:nickname).is_at_most(80) }

    it "requires sign_count to be >= 0" do
      cred = build(:passkey_credential, sign_count: -1)
      expect(cred).not_to be_valid
      expect(cred.errors[:sign_count]).to be_present
    end

    it "accepts sign_count 0" do
      expect(build(:passkey_credential, sign_count: 0)).to be_valid
    end
  end

  describe "transports" do
    it "defaults to an empty array when omitted" do
      user = create(:user)
      cred = PasskeyCredential.create!(
        user: user,
        external_id: "ext-1-#{SecureRandom.hex(4)}",
        public_key: "key",
        nickname: "Pk"
      )
      expect(cred.transports).to eq([])
    end

    it "stores an array of transport names" do
      cred = create(:passkey_credential, transports: %w[internal hybrid])
      expect(cred.reload.transports).to match_array(%w[internal hybrid])
    end
  end
end
