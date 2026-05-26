# frozen_string_literal: true

require "rails_helper"

RSpec.describe Opensop::AuthMode do
  # Restore all relevant ENV keys after every example so tests are isolated.
  around do |ex|
    orig_disable = ENV["OPENSOP_DISABLE_AUTH"]
    orig_rp_id   = ENV["OPENSOP_RP_ID"]
    orig_email   = ENV["OPENSOP_BOOTSTRAP_EMAIL"]
    ex.run
  ensure
    if orig_disable.nil?
      ENV.delete("OPENSOP_DISABLE_AUTH")
    else
      ENV["OPENSOP_DISABLE_AUTH"] = orig_disable
    end

    if orig_rp_id.nil?
      ENV.delete("OPENSOP_RP_ID")
    else
      ENV["OPENSOP_RP_ID"] = orig_rp_id
    end

    if orig_email.nil?
      ENV.delete("OPENSOP_BOOTSTRAP_EMAIL")
    else
      ENV["OPENSOP_BOOTSTRAP_EMAIL"] = orig_email
    end
  end

  # ------------------------------------------------------------------
  # .public_deployment?
  # ------------------------------------------------------------------
  describe ".public_deployment?" do
    context "when OPENSOP_RP_ID is a real domain" do
      it "returns true" do
        ENV["OPENSOP_RP_ID"] = "opensop.example.com"
        expect(described_class.public_deployment?).to be(true)
      end
    end

    context "when OPENSOP_RP_ID is 'localhost'" do
      it "returns false" do
        ENV["OPENSOP_RP_ID"] = "localhost"
        expect(described_class.public_deployment?).to be(false)
      end
    end

    context "when OPENSOP_RP_ID is '127.0.0.1'" do
      it "returns false" do
        ENV["OPENSOP_RP_ID"] = "127.0.0.1"
        expect(described_class.public_deployment?).to be(false)
      end
    end

    context "when OPENSOP_RP_ID is unset" do
      it "returns false" do
        ENV.delete("OPENSOP_RP_ID")
        expect(described_class.public_deployment?).to be(false)
      end
    end
  end

  # ------------------------------------------------------------------
  # .bypass?
  # ------------------------------------------------------------------
  describe ".bypass?" do
    context "truthiness — OPENSOP_DISABLE_AUTH accepts truthy strings case-insensitively" do
      before { ENV.delete("OPENSOP_RP_ID") } # non-public (localhost) context

      %w[true True TRUE 1 yes Yes YES on On ON].each do |truthy_val|
        it "returns true when OPENSOP_DISABLE_AUTH=#{truthy_val}" do
          ENV["OPENSOP_DISABLE_AUTH"] = truthy_val
          expect(described_class.bypass?).to be(true)
        end
      end
    end

    context "falsiness — OPENSOP_DISABLE_AUTH rejects falsey values" do
      before { ENV.delete("OPENSOP_RP_ID") }

      %w[false 0 no off].each do |falsey_val|
        it "returns false when OPENSOP_DISABLE_AUTH=#{falsey_val}" do
          ENV["OPENSOP_DISABLE_AUTH"] = falsey_val
          expect(described_class.bypass?).to be(false)
        end
      end

      it "returns false when OPENSOP_DISABLE_AUTH is empty string" do
        ENV["OPENSOP_DISABLE_AUTH"] = ""
        expect(described_class.bypass?).to be(false)
      end

      it "returns false when OPENSOP_DISABLE_AUTH is unset" do
        ENV.delete("OPENSOP_DISABLE_AUTH")
        expect(described_class.bypass?).to be(false)
      end
    end

    context "when OPENSOP_DISABLE_AUTH is truthy AND OPENSOP_RP_ID is unset (localhost context)" do
      it "returns true" do
        ENV["OPENSOP_DISABLE_AUTH"] = "true"
        ENV.delete("OPENSOP_RP_ID")
        expect(described_class.bypass?).to be(true)
      end
    end

    context "when OPENSOP_DISABLE_AUTH is truthy AND OPENSOP_RP_ID is 'localhost'" do
      it "returns true" do
        ENV["OPENSOP_DISABLE_AUTH"] = "true"
        ENV["OPENSOP_RP_ID"] = "localhost"
        expect(described_class.bypass?).to be(true)
      end
    end

    context "when OPENSOP_DISABLE_AUTH is truthy AND OPENSOP_RP_ID is '127.0.0.1'" do
      it "returns true" do
        ENV["OPENSOP_DISABLE_AUTH"] = "true"
        ENV["OPENSOP_RP_ID"] = "127.0.0.1"
        expect(described_class.bypass?).to be(true)
      end
    end

    context "when OPENSOP_DISABLE_AUTH is truthy BUT OPENSOP_RP_ID is a real domain (public deployment)" do
      it "returns false — public deployments must never bypass auth" do
        ENV["OPENSOP_DISABLE_AUTH"] = "true"
        ENV["OPENSOP_RP_ID"] = "opensop.example.com"
        expect(described_class.bypass?).to be(false)
      end
    end

    context "when OPENSOP_DISABLE_AUTH is falsey regardless of OPENSOP_RP_ID" do
      it "returns false even when OPENSOP_RP_ID is localhost" do
        ENV["OPENSOP_DISABLE_AUTH"] = "false"
        ENV["OPENSOP_RP_ID"] = "localhost"
        expect(described_class.bypass?).to be(false)
      end
    end
  end

  # ------------------------------------------------------------------
  # .bypass_user — resolution order
  # ------------------------------------------------------------------
  describe ".bypass_user" do
    before { ENV.delete("OPENSOP_BOOTSTRAP_EMAIL") }

    context "when OPENSOP_BOOTSTRAP_EMAIL is set and a matching user exists" do
      it "returns the user whose email matches (case-insensitive)" do
        bootstrap = create(:user, email: "admin@example.com")
        _other    = create(:user, email: "other@example.com")
        ENV["OPENSOP_BOOTSTRAP_EMAIL"] = "Admin@Example.COM"

        expect(described_class.bypass_user).to eq(bootstrap)
      end
    end

    context "when OPENSOP_BOOTSTRAP_EMAIL is set but no matching user exists" do
      it "falls through to the oldest admin user" do
        ENV["OPENSOP_BOOTSTRAP_EMAIL"] = "ghost@example.com"
        older = create(:user, email: "older@example.com")
        _newer = create(:user, email: "newer@example.com")
        # Ensure created_at ordering is meaningful
        older.update_columns(created_at: 2.days.ago)

        expect(described_class.bypass_user).to eq(older)
      end
    end

    context "when OPENSOP_BOOTSTRAP_EMAIL is unset" do
      it "returns the oldest admin user" do
        _newer = create(:user, email: "newer@example.com")
        older  = create(:user, email: "oldest@example.com")
        older.update_columns(created_at: 3.days.ago)

        expect(described_class.bypass_user).to eq(older)
      end
    end

    context "when no admin users exist but non-admin users do" do
      # The factory always creates role: "admin". Use `build` + manual role override
      # to test the fallback to any-user. Because all ROLES currently = ["admin"],
      # we model this scenario via a hypothetical future role by bypassing the
      # validation — OR we just verify the admin path is preferred when present.
      # For now, assert: if zero users at all, nil is returned.
      it "returns nil when there are no users at all" do
        expect(described_class.bypass_user).to be_nil
      end
    end
  end
end
