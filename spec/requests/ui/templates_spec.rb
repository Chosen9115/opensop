require "rails_helper"

# Covers GET /templates — file-driven (no DB writes) browseable template list.
# The route is wired in config/routes/ui.rb as
#   get "/templates", to: "ui/templates#index", as: :ui_templates
RSpec.describe "Ui::Templates", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  describe "GET /templates" do
    context "when the loader returns no templates" do
      before do
        allow(Opensop::TemplateLoader).to receive(:call).and_return([])
      end

      it "responds 200 and renders the empty state" do
        get "/templates"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Templates")
        expect(response.body).to include("No templates available")
      end
    end

    context "when the loader returns one or more templates" do
      let(:templates) do
        [
          {
            path: "processes/alpha.sop.yaml",
            name: "alpha",
            version: "1.0",
            description: "Alpha description",
            inputs_count: 2,
            outputs_count: 1,
            steps_count: 3,
            raw_yaml: "process:\n  name: alpha\n"
          },
          {
            path: "processes/beta.sop.yaml",
            name: "beta",
            version: "0.2",
            description: "Beta description",
            inputs_count: 0,
            outputs_count: 0,
            steps_count: 1,
            raw_yaml: "process:\n  name: beta\n"
          }
        ]
      end

      before do
        allow(Opensop::TemplateLoader).to receive(:call).and_return(templates)
      end

      it "renders one card per template with name, version, description, and counts" do
        get "/templates"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("alpha")
        expect(response.body).to include("v1.0")
        expect(response.body).to include("Alpha description")
        expect(response.body).to include("beta")
        expect(response.body).to include("v0.2")
        expect(response.body).to include("Beta description")
      end

      it "shows a 'View YAML' disclosure for each template" do
        get "/templates"

        expect(response.body).to include("View YAML")
        expect(response.body).to include("process:\n  name: alpha")
        expect(response.body).to include("process:\n  name: beta")
      end

      context "when a template name matches an existing Sop::Process" do
        let!(:imported) { create(:sop_process, name: "alpha", version: "1.0") }

        it "marks that template as imported and links to its existing process page" do
          get "/templates"

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("imported")
          expect(response.body).to include("/processes/alpha")
        end
      end

      context "when the Sop::Process table is unavailable" do
        before do
          allow(Sop::Process).to receive(:where)
            .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))
        end

        it "still renders the page without crashing" do
          get "/templates"

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("alpha")
          expect(response.body).to include("beta")
        end
      end
    end
  end
end
