require 'rails_helper'

RSpec.describe AuthSession, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "associations" do
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject { build(:auth_session) }

    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_uniqueness_of(:token_digest) }
    it { is_expected.to validate_presence_of(:expires_at) }
  end

  describe ".active scope" do
    it "excludes revoked and expired sessions" do
      live = create(:auth_session)
      _expired = create(:auth_session, expires_at: 1.minute.ago)
      _revoked = create(:auth_session, revoked_at: Time.current)

      expect(described_class.active).to contain_exactly(live)
    end
  end

  describe ".from_token" do
    let(:raw_token) { SecureRandom.urlsafe_base64(32) }
    let!(:session) do
      create(:auth_session, token_digest: Digest::SHA256.hexdigest(raw_token))
    end

    it "finds a session whose digest matches the SHA-256 of the raw token" do
      expect(described_class.from_token(raw_token)).to eq(session)
    end

    it "returns nil for a blank token" do
      expect(described_class.from_token("")).to be_nil
      expect(described_class.from_token(nil)).to be_nil
    end

    it "returns nil for a wrong token" do
      expect(described_class.from_token("not-the-token")).to be_nil
    end

    it "returns nil for an expired session" do
      session.update_columns(expires_at: 1.minute.ago)
      expect(described_class.from_token(raw_token)).to be_nil
    end

    it "returns nil for a revoked session" do
      session.update_columns(revoked_at: Time.current)
      expect(described_class.from_token(raw_token)).to be_nil
    end

    it "never persists the raw token in any column" do
      columns = AuthSession.columns.map(&:name)
      session_attrs = session.attributes
      columns.each do |col|
        value = session_attrs[col]
        next if value.nil?
        expect(value.to_s).not_to include(raw_token),
          "raw token should not appear in column #{col}"
      end
    end
  end

  describe "predicates" do
    it "#revoked? reflects revoked_at" do
      expect(build(:auth_session, revoked_at: nil).revoked?).to be false
      expect(build(:auth_session, revoked_at: Time.current).revoked?).to be true
    end

    it "#expired? reflects expires_at vs now" do
      expect(build(:auth_session, expires_at: 1.day.from_now).expired?).to be false
      expect(build(:auth_session, expires_at: 1.minute.ago).expired?).to be true
    end

    it "#usable? requires non-revoked and non-expired" do
      live = build(:auth_session)
      expect(live.usable?).to be true
      expect(build(:auth_session, revoked_at: Time.current).usable?).to be false
      expect(build(:auth_session, expires_at: 1.minute.ago).usable?).to be false
    end
  end

  describe "#touch_usage!" do
    it "always updates last_used_at" do
      session = create(:auth_session, expires_at: 10.days.from_now, last_used_at: nil)
      freeze_time = Time.current
      travel_to(freeze_time) do
        session.touch_usage!
      end
      expect(session.reload.last_used_at).to be_within(1.second).of(freeze_time)
    end

    it "does not extend expires_at when more than 24h remain" do
      original = 10.days.from_now
      session = create(:auth_session, expires_at: original)
      session.touch_usage!
      expect(session.reload.expires_at).to be_within(1.second).of(original)
    end

    it "extends expires_at when within 24h of expiry" do
      session = create(:auth_session, expires_at: 1.hour.from_now)
      session.touch_usage!(expires_in: 30.days)
      expect(session.reload.expires_at).to be > 29.days.from_now
    end
  end
end
