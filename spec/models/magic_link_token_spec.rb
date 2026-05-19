require 'rails_helper'

RSpec.describe MagicLinkToken, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject { build(:magic_link_token) }

    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_uniqueness_of(:token_digest) }
    it { is_expected.to validate_presence_of(:expires_at) }
    it { is_expected.to validate_inclusion_of(:purpose).in_array(MagicLinkToken::PURPOSES) }
  end

  describe ".usable scope" do
    it "excludes consumed and expired tokens" do
      live = create(:magic_link_token)
      _consumed = create(:magic_link_token, :consumed)
      _expired = create(:magic_link_token, :expired)

      expect(described_class.usable).to contain_exactly(live)
    end
  end

  describe ".from_token" do
    let(:raw_token) { SecureRandom.urlsafe_base64(32) }
    let!(:token) do
      create(:magic_link_token, token_digest: Digest::SHA256.hexdigest(raw_token))
    end

    it "finds a token whose digest matches the SHA-256 of the raw token" do
      expect(described_class.from_token(raw_token)).to eq(token)
    end

    it "returns nil for blank input" do
      expect(described_class.from_token(nil)).to be_nil
      expect(described_class.from_token("")).to be_nil
    end

    it "returns nil for a wrong token" do
      expect(described_class.from_token("nope")).to be_nil
    end

    it "returns nil after consumption" do
      token.update!(consumed_at: Time.current)
      expect(described_class.from_token(raw_token)).to be_nil
    end

    it "returns nil after expiration" do
      token.update_columns(expires_at: 1.minute.ago)
      expect(described_class.from_token(raw_token)).to be_nil
    end

    it "never persists the raw token in any column" do
      columns = MagicLinkToken.columns.map(&:name)
      attrs = token.attributes
      columns.each do |col|
        value = attrs[col]
        next if value.nil?
        expect(value.to_s).not_to include(raw_token),
          "raw token should not appear in column #{col}"
      end
    end
  end

  describe "predicates" do
    it "#consumed? reflects consumed_at" do
      expect(build(:magic_link_token).consumed?).to be false
      expect(build(:magic_link_token, :consumed).consumed?).to be true
    end

    it "#expired? reflects expires_at vs now" do
      expect(build(:magic_link_token).expired?).to be false
      expect(build(:magic_link_token, :expired).expired?).to be true
    end

    it "#usable? requires not-consumed and not-expired" do
      expect(build(:magic_link_token).usable?).to be true
      expect(build(:magic_link_token, :consumed).usable?).to be false
      expect(build(:magic_link_token, :expired).usable?).to be false
    end
  end

  describe "#consume!" do
    it "sets consumed_at to now" do
      token = create(:magic_link_token)
      freeze = Time.current
      travel_to(freeze) { token.consume! }
      expect(token.reload.consumed_at).to be_within(1.second).of(freeze)
    end

    it "makes the token unusable thereafter" do
      raw = SecureRandom.urlsafe_base64(32)
      token = create(:magic_link_token, token_digest: Digest::SHA256.hexdigest(raw))
      token.consume!
      expect(MagicLinkToken.from_token(raw)).to be_nil
    end
  end

  describe "purpose traits" do
    it "supports the :recovery trait" do
      expect(build(:magic_link_token, :recovery).purpose).to eq("recovery")
    end

    it "supports the :invitation trait with a longer expiry" do
      tok = build(:magic_link_token, :invitation)
      expect(tok.purpose).to eq("invitation")
      expect(tok.expires_at).to be > 6.days.from_now
    end
  end
end
