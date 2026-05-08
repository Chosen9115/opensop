require "rails_helper"

RSpec.describe Opensop::Auth::Mailer do
  let(:user)      { create(:user, email: "alice@example.com") }
  let(:inviter)   { create(:user, email: "ceo@example.com") }
  let(:raw_token) { "raw-token-abc123" }
  let(:host)      { "https://opensop.test" }

  before do
    # Always start in log mode unless a spec opts into send mode.
    ENV["OPENSOP_MAILER_MODE"] = "log"
    FileUtils.rm_rf(Rails.root.join("tmp", "opensop_emails"))
  end

  after do
    ENV.delete("OPENSOP_MAILER_MODE")
    ENV.delete("OPENSOP_MAILER_FROM")
  end

  describe ".send_magic_link" do
    context "in log mode" do
      it "writes an HTML file to tmp/opensop_emails/" do
        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
        files = Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s]
        expect(files.size).to eq(1)
        expect(File.read(files.first)).to include("#{host}/auth/magic_links/#{raw_token}")
      end

      it "logs the URL via Rails.logger.info" do
        log = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log)
        begin
          described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
        ensure
          Rails.logger = original_logger
        end
        expect(log.string).to include("#{host}/auth/magic_links/#{raw_token}")
      end

      it "returns a hash with an :id" do
        result = described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
        expect(result).to be_a(Hash)
        expect(result[:id]).to be_a(String)
        expect(result[:id]).to start_with("log-")
      end

      it "uses the magic_links path for sign_in" do
        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
        body = File.read(Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s].first)
        expect(body).to include("/auth/magic_links/#{raw_token}")
      end

      it "uses the magic_links path for recovery" do
        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "recovery", host: host)
        body = File.read(Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s].first)
        expect(body).to include("/auth/magic_links/#{raw_token}")
      end
    end

    context "in send mode" do
      before do
        ENV["OPENSOP_MAILER_MODE"] = "send"
        ENV["OPENSOP_MAILER_FROM"] = "noreply@opensop.dev"
      end

      it "calls Resend::Emails.send with the right payload" do
        captured = nil
        allow(Resend::Emails).to receive(:send) do |args|
          captured = args
          { id: "resend-id-123" }
        end

        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)

        expect(captured[:from]).to eq("noreply@opensop.dev")
        expect(captured[:to]).to eq([ "alice@example.com" ])
        expect(captured[:subject]).to eq(I18n.t("opensop.auth.emails.sign_in.subject"))
        expect(captured[:html]).to include("#{host}/auth/magic_links/#{raw_token}")
        expect(captured[:text]).to include("#{host}/auth/magic_links/#{raw_token}")
      end

      it "raises if OPENSOP_MAILER_FROM is missing" do
        ENV.delete("OPENSOP_MAILER_FROM")
        allow(Resend::Emails).to receive(:send)
        expect {
          described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
        }.to raise_error(KeyError)
      end
    end

    it "embeds the URL exactly once in the HTML href and once as a fallback link" do
      described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
      body = File.read(Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s].first)
      url = "#{host}/auth/magic_links/#{raw_token}"
      # The HTML body has the URL twice on purpose: once in the button href,
      # once as a copy-pasteable fallback. The text body has it once.
      expect(body.scan(url).size).to eq(2)
    end

    it "embeds the URL exactly once in the text body" do
      # Text body content is logged and visible to operators; verify by
      # peeking at the rails logger.
      log = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(log)
      begin
        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
      ensure
        Rails.logger = original_logger
      end
      url_count = log.string.scan("#{host}/auth/magic_links/#{raw_token}").size
      # Logger writes the URL once (the helper extracts it from the text body).
      expect(url_count).to eq(1)
    end

    it "raises ArgumentError on unknown purpose" do
      expect {
        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "garbage", host: host)
      }.to raise_error(ArgumentError, /Unknown purpose/)
    end
  end

  describe ".send_invitation" do
    context "in log mode" do
      it "uses the invitations path" do
        described_class.send_invitation(user: user, raw_token: raw_token, host: host, inviter: inviter)
        body = File.read(Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s].first)
        expect(body).to include("#{host}/auth/invitations/#{raw_token}")
      end

      it "includes the inviter's email when given" do
        described_class.send_invitation(user: user, raw_token: raw_token, host: host, inviter: inviter)
        body = File.read(Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s].first)
        expect(body).to include(ERB::Util.html_escape(inviter.email))
      end

      it "falls back to 'an administrator' when inviter is nil" do
        described_class.send_invitation(user: user, raw_token: raw_token, host: host, inviter: nil)
        body = File.read(Dir[Rails.root.join("tmp", "opensop_emails", "*.html").to_s].first)
        expect(body).to include(I18n.t("opensop.auth.emails.shared.an_admin"))
      end

      it "subject matches the invitation locale string" do
        # Capture via send mode for exact-subject assertion.
        ENV["OPENSOP_MAILER_MODE"] = "send"
        ENV["OPENSOP_MAILER_FROM"] = "noreply@opensop.dev"
        captured = nil
        allow(Resend::Emails).to receive(:send) { |args| captured = args; { id: "x" } }
        described_class.send_invitation(user: user, raw_token: raw_token, host: host, inviter: inviter)
        expect(captured[:subject]).to eq(I18n.t("opensop.auth.emails.invitation.subject"))
      end
    end
  end

  describe "mode dispatch" do
    it "raises ArgumentError on an unknown mode" do
      ENV["OPENSOP_MAILER_MODE"] = "carrier_pigeon"
      expect {
        described_class.send_magic_link(user: user, raw_token: raw_token, purpose: "sign_in", host: host)
      }.to raise_error(ArgumentError, /Unknown OPENSOP_MAILER_MODE/)
    end
  end
end
