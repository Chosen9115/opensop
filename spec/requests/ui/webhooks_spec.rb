require "rails_helper"

# Request spec for the Webhooks admin index page.
#
# NOTE: The route `GET /webhooks -> ui/webhooks#index` is added by the
# integration agent in `config/routes/ui.rb`. Until that ships these specs
# will fail with a routing error ("No route matches GET /webhooks") — that
# is expected. Once the integration agent wires the route, this file should
# pass without modification.
RSpec.describe "Ui::Webhooks", type: :request do
  before do
    sign_in_via_magic_link(create(:user))
  end

  describe "GET /webhooks" do
    context "when no callbacks exist" do
      it "returns 200 and renders the page header" do
        get "/webhooks"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Webhooks")
      end

      it "shows the empty state" do
        get "/webhooks"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No webhook callbacks yet")
      end

      it "still renders zero counts for each status tile" do
        get "/webhooks"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Pending")
        expect(response.body).to include("Received")
        expect(response.body).to include("Expired")
      end
    end

    context "when callbacks exist" do
      let!(:pending_callbacks) { create_list(:sop_callback, 2) }
      let!(:received_callback) { create(:sop_callback, :received) }
      let!(:expired_callback)  { create(:sop_callback, :expired) }

      it "returns 200 and lists recent callbacks" do
        get "/webhooks"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Recent callbacks")
      end

      it "renders one row per callback (showing the short callback id)" do
        get "/webhooks"

        Sop::Callback.find_each do |cb|
          short = cb.callback_path.to_s.split("/").last.to_s.first(12)
          expect(response.body).to include(short),
            "expected response to include short callback id #{short}"
        end
      end

      it "displays grouped counts for each status" do
        get "/webhooks"

        # Counts (2 pending, 1 received, 1 expired) — verify the tiles have
        # the right values rendered. Match the inline 28px hero number used
        # by the Paper Pro tile.
        expect(response.body).to match(/text-\[28px\][^>]*>\s*2\s*</)
        expect(response.body).to match(/text-\[28px\][^>]*>\s*1\s*</)
      end

      it "links each row to its associated instance" do
        get "/webhooks"

        Sop::Callback.includes(:instance).find_each do |cb|
          expect(response.body).to include("/instances/#{cb.instance.id}"),
            "expected response to link to instance #{cb.instance.id}"
        end
      end

      it "shows the step_id for each callback" do
        get "/webhooks"

        Sop::Callback.find_each do |cb|
          expect(response.body).to include(cb.step_id)
        end
      end
    end
  end
end
