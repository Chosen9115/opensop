require "rails_helper"

RSpec.describe Opensop::Auth::TokenIssuer do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe ".call" do
    it "creates a MagicLinkToken row tied to the user" do
      expect {
        described_class.call(user: user, purpose: "sign_in")
      }.to change(user.magic_link_tokens, :count).by(1)
    end

    it "returns the raw token to the caller" do
      raw = described_class.call(user: user, purpose: "sign_in")
      expect(raw).to be_a(String)
      expect(raw.length).to be >= 32
    end

    it "stores only the SHA-256 digest of the raw token" do
      raw = described_class.call(user: user, purpose: "sign_in")
      token = user.magic_link_tokens.last
      expect(token.token_digest).to eq(Digest::SHA256.hexdigest(raw))
    end

    it "does not persist the raw token in any column" do
      raw = described_class.call(user: user, purpose: "sign_in")
      token = user.magic_link_tokens.last

      token.attributes.each_value do |value|
        expect(value.to_s).not_to eq(raw), "Raw token leaked into a column: #{value.inspect}"
      end
    end

    it "is round-trippable via MagicLinkToken.from_token" do
      raw = described_class.call(user: user, purpose: "sign_in")
      expect(MagicLinkToken.from_token(raw)).to eq(user.magic_link_tokens.last)
    end

    context "default TTLs by purpose" do
      it "uses 15 minutes for sign_in" do
        freeze_time do
          described_class.call(user: user, purpose: "sign_in")
          token = user.magic_link_tokens.last
          expect(token.expires_at).to be_within(1.second).of(15.minutes.from_now)
        end
      end

      it "uses 15 minutes for recovery" do
        freeze_time do
          described_class.call(user: user, purpose: "recovery")
          token = user.magic_link_tokens.last
          expect(token.expires_at).to be_within(1.second).of(15.minutes.from_now)
        end
      end

      it "uses 7 days for invitation" do
        freeze_time do
          described_class.call(user: user, purpose: "invitation")
          token = user.magic_link_tokens.last
          expect(token.expires_at).to be_within(1.second).of(7.days.from_now)
        end
      end

      it "falls back to 15 minutes for unknown purposes (defensive)" do
        freeze_time do
          # purpose "sign_in" is valid; we test the default branch by passing
          # an unknown but-still-arbitrary string and stubbing validation off.
          # Use a known purpose here since model validations will reject
          # unknowns. The fallback is exercised in the unit-level branch.
          allow_any_instance_of(MagicLinkToken).to receive(:valid?).and_return(true)
          token = nil
          allow(user.magic_link_tokens).to receive(:create!).and_wrap_original do |m, **attrs|
            token = m.call(token_digest: attrs[:token_digest], purpose: "sign_in", expires_at: attrs[:expires_at], requested_ip: attrs[:requested_ip])
          end
          described_class.call(user: user, purpose: "totally_unknown_purpose")
          expect(token.expires_at).to be_within(1.second).of(15.minutes.from_now)
        end
      end
    end

    it "honors a custom expires_in" do
      freeze_time do
        described_class.call(user: user, purpose: "sign_in", expires_in: 1.hour)
        token = user.magic_link_tokens.last
        expect(token.expires_at).to be_within(1.second).of(1.hour.from_now)
      end
    end

    it "persists the requested_ip" do
      described_class.call(user: user, purpose: "sign_in", requested_ip: "203.0.113.42")
      token = user.magic_link_tokens.last
      expect(token.requested_ip).to eq("203.0.113.42")
    end

    it "stores the purpose" do
      described_class.call(user: user, purpose: "invitation")
      token = user.magic_link_tokens.last
      expect(token.purpose).to eq("invitation")
    end

    it "issues distinct raw tokens across calls" do
      raw1 = described_class.call(user: user, purpose: "sign_in")
      raw2 = described_class.call(user: user, purpose: "sign_in")
      expect(raw1).not_to eq(raw2)
    end
  end
end
