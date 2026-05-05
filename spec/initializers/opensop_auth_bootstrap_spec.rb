require "rails_helper"

RSpec.describe Opensop::Auth::Bootstrap do
  let(:bootstrap_email) { "founder@example.com" }

  before do
    ENV["OPENSOP_BOOTSTRAP_EMAIL"] = bootstrap_email
    ENV["OPENSOP_ORIGIN"] = "https://opensop.test"
    File.delete(Rails.root.join("tmp", "opensop_first_login.txt")) if File.exist?(Rails.root.join("tmp", "opensop_first_login.txt"))
  end

  after do
    ENV.delete("OPENSOP_BOOTSTRAP_EMAIL")
    ENV.delete("OPENSOP_ORIGIN")
  end

  describe ".run!" do
    context "cold start (no users exist)" do
      it "creates the bootstrap user with role admin" do
        expect { described_class.run! }.to change(User, :count).by(1)
        user = User.last
        expect(user.email).to eq(bootstrap_email)
        expect(user.role).to eq("admin")
        expect(user.display_name).to eq("Bootstrap admin")
      end

      it "issues an invitation token for the bootstrap user" do
        expect { described_class.run! }.to change(MagicLinkToken, :count).by(1)
        token = MagicLinkToken.last
        expect(token.purpose).to eq("invitation")
        expect(token.consumed_at).to be_nil
      end

      it "writes the first-login URL to tmp/opensop_first_login.txt" do
        described_class.run!
        path = Rails.root.join("tmp", "opensop_first_login.txt")
        expect(File.exist?(path)).to be(true)
        contents = File.read(path)
        expect(contents).to start_with("https://opensop.test/auth/invitations/")
      end

      it "chmods the tmp file to 0600" do
        described_class.run!
        path = Rails.root.join("tmp", "opensop_first_login.txt")
        mode = File.stat(path).mode & 0o777
        expect(mode).to eq(0o600)
      end

      it "logs the URL via Rails.logger" do
        log = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log)
        begin
          described_class.run!
        ensure
          Rails.logger = original_logger
        end
        expect(log.string).to match(%r{https://opensop\.test/auth/invitations/})
      end

      it "returns the issued URL" do
        result = described_class.run!
        expect(result).to start_with("https://opensop.test/auth/invitations/")
      end
    end

    context "restart with bootstrap user but no passkeys and no usable token" do
      let!(:user) { create(:user, email: bootstrap_email) }

      it "regenerates an invitation token" do
        expect { described_class.run! }.to change(user.magic_link_tokens, :count).by(1)
        expect(user.magic_link_tokens.last.purpose).to eq("invitation")
      end

      it "does not create a duplicate user" do
        expect { described_class.run! }.not_to change(User, :count)
      end
    end

    context "restart with bootstrap user that already has a usable token" do
      let!(:user) { create(:user, email: bootstrap_email) }
      let!(:token) do
        Opensop::Auth::TokenIssuer.call(user: user, purpose: "invitation")
        user.magic_link_tokens.last
      end

      it "is a no-op (no new tokens issued)" do
        expect { described_class.run! }.not_to change(MagicLinkToken, :count)
      end
    end

    context "restart with bootstrap user that has a passkey" do
      let!(:user) { create(:user, email: bootstrap_email) }
      let!(:passkey) { create(:passkey_credential, user: user) }

      it "is a no-op (no new tokens, no new users)" do
        expect { described_class.run! }.not_to change(MagicLinkToken, :count)
        expect { described_class.run! }.not_to change(User, :count)
      end
    end

    context "users exist but none match the bootstrap email" do
      let!(:other_user) { create(:user, email: "other@example.com") }

      it "is a no-op — does not create the bootstrap user or issue tokens" do
        expect { described_class.run! }.not_to change(User, :count)
        expect { described_class.run! }.not_to change(MagicLinkToken, :count)
      end
    end

    context "OPENSOP_BOOTSTRAP_EMAIL is unset" do
      before { ENV.delete("OPENSOP_BOOTSTRAP_EMAIL") }

      it "is a no-op" do
        expect { described_class.run! }.not_to change(User, :count)
        expect { described_class.run! }.not_to change(MagicLinkToken, :count)
      end
    end

    context "OPENSOP_BOOTSTRAP_EMAIL is blank/whitespace" do
      before { ENV["OPENSOP_BOOTSTRAP_EMAIL"] = "   " }

      it "is a no-op" do
        expect { described_class.run! }.not_to change(User, :count)
      end
    end

    context "DB is not ready" do
      it "rescues StatementInvalid and logs a warning" do
        allow(User).to receive(:count).and_raise(ActiveRecord::StatementInvalid.new("PG::UndefinedTable"))

        log = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log, level: Logger::WARN)
        begin
          expect { described_class.run! }.not_to raise_error
        ensure
          Rails.logger = original_logger
        end
        expect(log.string).to include("Bootstrap skipped (DB not ready)")
      end

      it "rescues NoDatabaseError and logs a warning" do
        allow(User).to receive(:count).and_raise(ActiveRecord::NoDatabaseError.new("no db"))

        log = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log, level: Logger::WARN)
        begin
          expect { described_class.run! }.not_to raise_error
        ensure
          Rails.logger = original_logger
        end
        expect(log.string).to include("Bootstrap skipped (DB not ready)")
      end
    end

    context "case sensitivity" do
      before { ENV["OPENSOP_BOOTSTRAP_EMAIL"] = "  Founder@Example.COM  " }

      it "normalizes the email to lowercase + stripped" do
        described_class.run!
        expect(User.last.email).to eq("founder@example.com")
      end
    end
  end
end
