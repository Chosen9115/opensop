# frozen_string_literal: true

require "rails_helper"

# config/initializers/admin_ui_auth.rb is the boot-time guard that prevents
# a production deploy from coming up without OPENSOP_UI_USER /
# OPENSOP_UI_PASSWORD set. It runs once at process start, so we exercise
# it here by re-loading the file under stubbed Rails.env conditions.
RSpec.describe "config/initializers/admin_ui_auth.rb" do
  let(:initializer_path) { Rails.root.join("config/initializers/admin_ui_auth.rb") }

  around do |example|
    saved_user = ENV["OPENSOP_UI_USER"]
    saved_pass = ENV["OPENSOP_UI_PASSWORD"]
    example.run
  ensure
    ENV["OPENSOP_UI_USER"]     = saved_user
    ENV["OPENSOP_UI_PASSWORD"] = saved_pass
  end

  context "in production" do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))
    end

    it "raises when both env vars are missing" do
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")

      expect { load initializer_path }
        .to raise_error(/OPENSOP_UI_USER and OPENSOP_UI_PASSWORD must both be set/)
    end

    it "raises when only OPENSOP_UI_USER is set" do
      ENV["OPENSOP_UI_USER"] = "admin"
      ENV.delete("OPENSOP_UI_PASSWORD")

      expect { load initializer_path }.to raise_error(/OPENSOP_UI_USER and OPENSOP_UI_PASSWORD/)
    end

    it "raises when only OPENSOP_UI_PASSWORD is set" do
      ENV.delete("OPENSOP_UI_USER")
      ENV["OPENSOP_UI_PASSWORD"] = "secret"

      expect { load initializer_path }.to raise_error(/OPENSOP_UI_USER and OPENSOP_UI_PASSWORD/)
    end

    it "raises when env vars are present but blank" do
      ENV["OPENSOP_UI_USER"]     = "  "
      ENV["OPENSOP_UI_PASSWORD"] = ""

      expect { load initializer_path }.to raise_error(/OPENSOP_UI_USER and OPENSOP_UI_PASSWORD/)
    end

    it "boots cleanly when both env vars are set" do
      ENV["OPENSOP_UI_USER"]     = "admin"
      ENV["OPENSOP_UI_PASSWORD"] = "secret"

      expect { load initializer_path }.not_to raise_error
    end
  end

  context "in development" do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
    end

    it "does NOT raise when env vars are missing — dev falls back to defaults" do
      expect { load initializer_path }.not_to raise_error
    end
  end

  context "in test" do
    before do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("test"))
      ENV.delete("OPENSOP_UI_USER")
      ENV.delete("OPENSOP_UI_PASSWORD")
    end

    it "does NOT raise when env vars are missing — tests opt out" do
      expect { load initializer_path }.not_to raise_error
    end
  end
end
