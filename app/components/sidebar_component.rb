class SidebarComponent < ViewComponent::Base
  # Renders the 220px Paper Pro left sidebar: brand, search prompt, two
  # nav sections (Workspace, Library), and an API status footer.
  #
  # Usage:
  #   <%= render SidebarComponent.new(
  #         current_path: request.path,
  #         counts: { processes: 12, instances_running: 3, instances_waiting: 1 }
  #       ) %>
  def initialize(current_path:, counts:)
    @current_path = current_path.to_s
    @counts = counts || {}
  end

  attr_reader :current_path, :counts

  def version_label
    if defined?(Opensop::VERSION)
      "v#{Opensop::VERSION}"
    else
      "v0.2"
    end
  end

  def workspace_items
    [
      { key: :dashboard,
        label: I18n.t("opensop.nav.dashboard", default: "Dashboard"),
        icon: :home,
        path: helpers.ui_dashboard_path,
        active: dashboard_active?,
        disabled: false },
      { key: :processes,
        label: I18n.t("opensop.nav.processes", default: "Processes"),
        icon: :squares_2x2,
        path: helpers.ui_processes_path,
        active: path_active?(helpers.ui_processes_path),
        badge: counts[:processes],
        disabled: false },
      { key: :instances,
        label: I18n.t("opensop.nav.instances", default: "Instances"),
        icon: :squares_plus,
        path: helpers.ui_instances_path,
        active: path_active?(helpers.ui_instances_path),
        badge: counts[:instances_running],
        live: true,
        disabled: false },
      { key: :schedule,
        label: I18n.t("opensop.nav.schedule", default: "Schedule"),
        icon: :calendar,
        disabled: true },
      { key: :agents,
        label: I18n.t("opensop.nav.agents", default: "Agents"),
        icon: :users,
        path: helpers.ui_agents_path,
        active: path_active?(helpers.ui_agents_path),
        disabled: false },
      { key: :costs,
        label: I18n.t("opensop.nav.costs", default: "Costs"),
        icon: :currency_dollar,
        path: helpers.ui_costs_path,
        active: path_active?(helpers.ui_costs_path),
        disabled: false },
      { key: :metrics,
        label: I18n.t("opensop.nav.metrics", default: "Metrics"),
        icon: :chart_bar,
        path: helpers.ui_metrics_path,
        active: path_active?(helpers.ui_metrics_path),
        disabled: false }
    ]
  end

  def library_items
    [
      { key: :templates,
        label: I18n.t("opensop.nav.templates", default: "Templates"),
        icon: :document_duplicate,
        path: helpers.ui_templates_path,
        active: path_active?(helpers.ui_templates_path),
        disabled: false },
      { key: :webhooks,
        label: I18n.t("opensop.nav.webhooks", default: "Webhooks"),
        icon: :bolt,
        path: helpers.ui_webhooks_path,
        active: path_active?(helpers.ui_webhooks_path),
        disabled: false },
      { key: :api,
        label: I18n.t("opensop.nav.api", default: "API & SDK"),
        icon: :arrow_top_right_on_square,
        path: helpers.ui_api_docs_path,
        active: path_active?(helpers.ui_api_docs_path),
        disabled: false }
    ]
  end

  def link_classes(item)
    base = "flex items-center gap-2 px-3 py-1.5 text-[12px] cursor-pointer rounded-[3px]"
    if item[:disabled]
      "#{base} text-fg-faint cursor-not-allowed pointer-events-none opacity-60"
    elsif item[:active]
      "#{base} text-fg bg-bg-hover font-medium relative " \
        "before:absolute before:left-0 before:top-0 before:bottom-0 before:w-[2px] before:bg-fg"
    else
      "#{base} text-fg-muted hover:bg-bg-hover hover:text-fg"
    end
  end

  def badge_classes(item)
    base = "ml-auto pp-tag"
    item[:live] ? "#{base} text-info" : base
  end

  def coming_soon_title
    I18n.t("opensop.common.coming_soon", default: "Coming soon")
  end

  def api_authenticated?
    helpers.respond_to?(:api_token_active?) && helpers.api_token_active?
  end

  def icon_path(name)
    ICONS[name] || ICONS[:home]
  end

  # Heroicons mini-outline 16x16 path data, sourced from heroicons.com.
  # Inlined because importmap doesn't handle icon libraries.
  ICONS = {
    home: "M11.47 3.84a.75.75 0 011.06 0l8.69 8.69a.75.75 0 101.06-1.06l-8.689-8.69a2.25 2.25 0 00-3.182 0l-8.69 8.69a.75.75 0 001.061 1.06l8.69-8.69z M12 5.432l8.159 8.159c.03.03.06.058.091.086v6.198c0 1.035-.84 1.875-1.875 1.875H15a.75.75 0 01-.75-.75v-4.5a.75.75 0 00-.75-.75h-3a.75.75 0 00-.75.75V21a.75.75 0 01-.75.75H5.625a1.875 1.875 0 01-1.875-1.875v-6.198a2.29 2.29 0 00.091-.086L12 5.43z",
    squares_2x2: "M3 6a3 3 0 013-3h2.25a3 3 0 013 3v2.25a3 3 0 01-3 3H6a3 3 0 01-3-3V6zM3 15.75a3 3 0 013-3h2.25a3 3 0 013 3V18a3 3 0 01-3 3H6a3 3 0 01-3-3v-2.25zM12.75 6a3 3 0 013-3H18a3 3 0 013 3v2.25a3 3 0 01-3 3h-2.25a3 3 0 01-3-3V6zM12.75 15.75a3 3 0 013-3H18a3 3 0 013 3V18a3 3 0 01-3 3h-2.25a3 3 0 01-3-3v-2.25z",
    squares_plus: "M6 3a3 3 0 00-3 3v2.25a3 3 0 003 3h2.25a3 3 0 003-3V6a3 3 0 00-3-3H6zM17.25 3a.75.75 0 01.75.75V6.75H21a.75.75 0 010 1.5h-2.99V11.25a.75.75 0 01-1.5 0V8.25H13.5a.75.75 0 010-1.5h2.99V3.75a.75.75 0 01.75-.75zM6 12.75a3 3 0 00-3 3V18a3 3 0 003 3h2.25a3 3 0 003-3v-2.25a3 3 0 00-3-3H6zM17.625 13.5a3.375 3.375 0 00-3.375 3.375v.75c0 1.864 1.511 3.375 3.375 3.375h.75A3.375 3.375 0 0021.75 17.625v-.75A3.375 3.375 0 0018.375 13.5h-.75z",
    calendar: "M12 6.75a.75.75 0 110-1.5.75.75 0 010 1.5zM7.5 6.75a.75.75 0 110-1.5.75.75 0 010 1.5zM16.5 6.75a.75.75 0 110-1.5.75.75 0 010 1.5z M6.75 2.25a.75.75 0 01.75.75V4.5h9V3a.75.75 0 011.5 0v1.5h.75a3 3 0 013 3v11.25a3 3 0 01-3 3H5.25a3 3 0 01-3-3V7.5a3 3 0 013-3H6V3a.75.75 0 01.75-.75zm13.5 9a1.5 1.5 0 00-1.5-1.5H5.25a1.5 1.5 0 00-1.5 1.5v7.5a1.5 1.5 0 001.5 1.5h13.5a1.5 1.5 0 001.5-1.5v-7.5z",
    users: "M4.5 6.375a4.125 4.125 0 118.25 0 4.125 4.125 0 01-8.25 0zM14.25 8.625a3.375 3.375 0 116.75 0 3.375 3.375 0 01-6.75 0zM1.5 19.125a7.125 7.125 0 0114.25 0v.003l-.001.119a.75.75 0 01-.363.63 13.067 13.067 0 01-6.761 1.873c-2.472 0-4.786-.684-6.76-1.873a.75.75 0 01-.364-.63l-.001-.122zM17.25 19.128l-.001.144a2.25 2.25 0 01-.233.96 10.088 10.088 0 005.06-1.01.75.75 0 00.42-.643 4.875 4.875 0 00-6.957-4.611 8.586 8.586 0 011.71 5.157v.003z",
    currency_dollar: "M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25zM12.75 6a.75.75 0 00-1.5 0v.816a3.836 3.836 0 00-1.72.756c-.712.566-1.112 1.35-1.112 2.178 0 .832.4 1.612 1.113 2.178.502.4 1.102.679 1.719.756v3.804c-.426-.054-.835-.165-1.215-.327-.382-.165-.74-.385-1.062-.654a.75.75 0 10-.952 1.16 5.51 5.51 0 003.229 1.345v.866a.75.75 0 001.5 0v-.86a4.535 4.535 0 002.176-.913c.712-.566 1.112-1.35 1.112-2.178 0-.832-.4-1.612-1.113-2.178a4.535 4.535 0 00-2.175-.913V8.443c.66.084 1.31.296 1.875.679a.75.75 0 10.836-1.246 5.412 5.412 0 00-2.71-1.06V6z",
    chart_bar: "M18.375 2.25c-1.035 0-1.875.84-1.875 1.875v15.75c0 1.035.84 1.875 1.875 1.875h.75c1.035 0 1.875-.84 1.875-1.875V4.125c0-1.036-.84-1.875-1.875-1.875h-.75zM9.75 8.625c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v11.25c0 1.035-.84 1.875-1.875 1.875h-.75a1.875 1.875 0 01-1.875-1.875V8.625zM3 13.125c0-1.036.84-1.875 1.875-1.875h.75c1.036 0 1.875.84 1.875 1.875v6.75c0 1.035-.84 1.875-1.875 1.875h-.75A1.875 1.875 0 013 19.875v-6.75z",
    document_duplicate: "M7.5 3.75A1.5 1.5 0 006 5.25v13.5a1.5 1.5 0 001.5 1.5h6a1.5 1.5 0 001.5-1.5V15a.75.75 0 011.5 0v3.75a3 3 0 01-3 3h-6a3 3 0 01-3-3V5.25a3 3 0 013-3H10.5a.75.75 0 010 1.5h-3z M16.5 6.75a.75.75 0 01.75-.75h3.75a.75.75 0 01.75.75v3.75a.75.75 0 01-1.5 0V8.56l-7.72 7.72a.75.75 0 11-1.06-1.06l7.72-7.72H17.25a.75.75 0 01-.75-.75z",
    bolt: "M14.615 1.595a.75.75 0 01.359.852L12.982 9.75h7.268a.75.75 0 01.548 1.262l-10.5 11.25a.75.75 0 01-1.272-.71l1.992-7.302H3.75a.75.75 0 01-.548-1.262l10.5-11.25a.75.75 0 01.913-.143z",
    arrow_top_right_on_square: "M15.75 2.25H21a.75.75 0 01.75.75v5.25a.75.75 0 01-1.5 0V4.81L8.03 17.03a.75.75 0 01-1.06-1.06L19.19 3.75h-3.44a.75.75 0 010-1.5z M5.25 6.75a3 3 0 00-3 3v9a3 3 0 003 3h9a3 3 0 003-3V13.5a.75.75 0 00-1.5 0v5.25a1.5 1.5 0 01-1.5 1.5h-9a1.5 1.5 0 01-1.5-1.5v-9a1.5 1.5 0 011.5-1.5h5.25a.75.75 0 000-1.5H5.25z",
    search: "M10.5 3.75a6.75 6.75 0 100 13.5 6.75 6.75 0 000-13.5zM2.25 10.5a8.25 8.25 0 1114.59 5.28l4.69 4.69a.75.75 0 11-1.06 1.06l-4.69-4.69A8.25 8.25 0 012.25 10.5z"
  }.freeze

  private

  def dashboard_active?
    @current_path == "/" || @current_path == helpers.ui_dashboard_path
  end

  def path_active?(path)
    return false if path.blank?
    @current_path == path || @current_path.start_with?("#{path}/")
  end
end
