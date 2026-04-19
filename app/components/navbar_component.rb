class NavbarComponent < ViewComponent::Base
  def initialize(current_path:)
    @current_path = current_path.to_s
  end

  def nav_items
    [
      {
        key: :dashboard,
        label: I18n.t("opensop.nav.dashboard"),
        path: helpers.ui_dashboard_path,
        paths: ["/", "/dashboard"],
        disabled: false
      },
      {
        key: :processes,
        label: I18n.t("opensop.nav.processes"),
        path: helpers.ui_processes_path,
        paths: ["/processes"],
        disabled: false
      },
      {
        key: :instances,
        label: I18n.t("opensop.nav.instances"),
        path: helpers.ui_instances_path,
        paths: ["/instances"],
        disabled: false
      },
      {
        key: :metrics,
        label: I18n.t("opensop.nav.metrics"),
        path: "#",
        paths: [],
        disabled: true
      }
    ]
  end

  def active?(item)
    return false if item[:disabled]
    Array(item[:paths]).any? do |p|
      p == "/" ? @current_path == "/" : (@current_path == p || @current_path.start_with?("#{p}/"))
    end
  end

  def api_token_active?
    ENV["OPENSOP_API_TOKEN"].to_s.strip != ""
  end
end
