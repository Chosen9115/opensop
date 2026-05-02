# OpenSOP API Reference — Redesign Spec

**Source design:** `/Users/abrahamkuri/Downloads/OpenSOP API Docs - standalone.html`
(a Pencil/.pen bundled standalone HTML — open in a browser to view)

This is the **source of truth** for the rebuild. The design must match exactly.

---

## 1. Scope

Replace the current single-page `/api-docs` (one ERB view, simple table) with
a multi-page reference site that lives at `/api-docs` and uses its OWN custom
layout (no main app sidebar, no activity rail). The current
`Ui::ApiDocsController#index` and `app/views/ui/api_docs/index.html.erb` get
fully replaced.

**Pages:**
1. **Guides** (long-form prose):
   - `quickstart` — landing, "From zero to a running process instance in
     under five minutes." 4 numbered steps + Lifecycle diagram + Next steps
   - `authentication` — three auth modes (bearer / HMAC / single-use callback),
     Token rotation table
   - `process-format` — YAML schema anatomy, Step-types table, References ($${...} syntax)
   - `errors` — error JSON Shape, Status-codes table, Retries
   - `versioning` — API version table, Process versions
2. **Endpoint detail pages** (one per endpoint, dark code panel on the right):
   - DISCOVERY: `GET /sop/`, `GET /sop/:name/schema`
   - PROCESSES: `POST /processes/register`
   - INSTANCES: `GET /sop/instances`, `POST /sop/:name/start`,
     `GET /sop/:name/:id`, `POST /sop/:name/:id/cancel`
   - STEPS: `GET /sop/:name/:id/steps`,
     `POST /sop/:name/:id/steps/:step_id/submit`, `GET /sop/steps/pending`
   - WEBHOOK TRIGGERS: `POST /sop/triggers/:process_name`
   - WEBHOOK CALLBACKS: `POST /sop/webhooks/:callback_id`
   - METRICS: `GET /sop/metrics`

---

## 2. Layout (custom — `layouts/api_docs.html.erb`)

```
┌──────────────────────────────────────────────────────────────────┐
│ TOPBAR (h=48)  ▣ OpenSOP  [API Reference] (v0.1)   ...   [search]│
├────────┬─────────────────────────────────────────────────────────┤
│SIDEBAR │ MAIN content (page-specific)                            │
│ 240px  │ - guides:    1 col                                      │
│ #f7f8fa│ - endpoints: 2 cols (left prose ~58%, right code 42%)   │
│        │                                                         │
└────────┴─────────────────────────────────────────────────────────┘
```

- Topbar background: `#fff`, bottom border `#eaecef`, height 48px, padding-x 24
- Sidebar background: `#f7f8fa`, right border `#eaecef`, width 240px, full height
- Main content max-width naturally fills remaining width; content-area
  uses 32–40px horizontal padding

**No main `SidebarComponent`, no `ActivityRailComponent`.** Set
`show_rail?` is irrelevant — this layout does not render the standard chrome.

---

## 3. Topbar

Left to right:
- Brand: 4-square 20×20 grid logo (top-left + bottom-right `#0f1115`,
  the other two `#5d6470`). Each square 9×9 with 2px gap.
- Wordmark: "OpenSOP" — Inter 14px/600 `#0f1115`
- Section tag: "API Reference" — Inter 12px/500 `#5d6470`
- Version pill: "v0.1" — mono 11px in `#eef0f3` pill, padding 2/6, radius 3
- Spacer (flex-grow)
- Nav links: Dashboard, Changelog, GitHub (with octocat svg) — Inter 12px
  `#5d6470` hover `#0f1115`. Dashboard goes to `ui_dashboard_path`.
  GitHub goes to `https://github.com/Chosen9115/opensop` (use Opensop config if exists).
- Search input: width ~280px, `#fff` bg, border `#eaecef`, radius 3,
  height 28, padding-l 32 (search icon left), placeholder "Search reference…"
  `#9aa0a8`, with `⌘K` kbd hint at the right edge (mono 10px in pill).

The search box is a **non-functional UI placeholder** for now (matches the
design — clicking it focuses; no real search backend). Stub it as a plain
input with no submit handler. Capture the path for future enhancement.

---

## 4. Sidebar

Sections with header label + count, then link rows. Section spacing 16px.

```
GETTING STARTED                5
  Quickstart   →
  Authentication →
  Process format →
  Errors       →
  Versioning   →

DISCOVERY                      2
  GET  /
  GET  /:name/schema

PROCESSES                      1
  POST /processes/register

INSTANCES                      4
  GET  /instances
  POST /:name/start    ← active
  GET  /:name/:id
  POST /:name/:id/cancel

STEPS                          3
  GET  /:name/:id/steps
  POST /:name/:id/steps/:s…
  GET  /steps/pending

WEBHOOK TRIGGERS               1
  POST /triggers/:process_…

WEBHOOK CALLBACKS              1
  POST /webhooks/:callback…

METRICS                        1
  GET  /metrics
```

**`.sb-section`** — uppercase 9px `#9aa0a8` letter-spaced 0.06em with the
count as a faint mono pill on the right.

**`.sb-link`** — 28px row height, padding-l 14, padding-r 8, font 12.
Default: text `#5d6470`. Hover: bg `#f0f2f5`. Active (`.on`):
- bg `#fff`
- left rail: 2px wide black bar at left edge (use `box-shadow: inset 2px 0 0 #0f1115`)
- text color `#0f1115` font-weight 500
- subtle shadow `0 1px 2px rgba(0,0,0,0.04)`

**Guide links** (`.sb-link.guide`): label + `→` arrow on right (`#9aa0a8`).

**Endpoint links**: small `<span class="meth get">GET</span>` (mono 9px,
weight 600, color `#1f4ed8` for GET, `#0f7a3d` for POST, `#b03333` for DELETE)
+ truncated path in mono 11px `#0f1115`. Long paths show ellipsis.

---

## 5. Page header (every page)

```
api / discovery / list all processes        ← breadcrumb (mono 11px #9aa0a8, '/' #d5d8de)
List all processes                          ← <h1> Inter 28px/600 #0f1115
[GET] /sop/                                 ← method badge + mono path (only on endpoint pages)
A short prose description...                ← Inter 14px/400 #5d6470 max-w prose
─────────────────────────────────────────── ← divider #eaecef
```

Breadcrumb spacing: 2px between segments and slashes. Slashes are
plain `/` in faint color.

---

## 6. Components & shared elements

### MethodBadge (`<span class="meth-badge">`)
```
GET    bg #e3ebfd  fg #1f4ed8
POST   bg #e7f6ec  fg #0f7a3d
DELETE bg #fbe9e9  fg #b03333
PATCH  bg #fdf3d6  fg #946700
```
Shape: rounded `3px`, padding `3px 8px`, mono 10px weight 600.
On endpoint pages the badge sits to the LEFT of the inline path, with
8px gap. Path itself is mono 14px `#0f1115`. Use `:name` highlighted
distinctly (slightly different color e.g. `#1f4ed8` for params).

### Callout (`<div class="callout callout--info">`)
Left-bordered colored block. Variants:
- info  — bg `#e3ebfd80` (or `#eef4ff`), border-left `4px #1f4ed8`, label "AUTH" or "PREREQ"
- warn  — bg `#fdf3d680`, border-left `4px #946700`, label "IMPORTANT"

Padding 12 16, radius 3 (right side only). Label is mono 10px weight 700
uppercase, inline before body text. 8px gap between label and body.

### CodePanel (`<div class="code-panel">`)
Dark theme block. Background `#0f1115`, border `#2a2f3a` (1px), radius 4.

**Header bar** (h=36, border-b `#2a2f3a`, padding-x 12):
- Left: tabs OR a static label (e.g. "RESPONSE" or "REQUEST BODY · application/json")
- Right: `Copy` button — mono 10px `#a4abb8` with copy icon, hover `#fff`

**Tabs:**  curl / node / python / ruby — mono 11px, padding 6/10, active tab
has `#1a1d24` bg + `#fff` fg + 1px bottom highlight `#1f4ed8`.

**Body** (padding 16, mono 12px, line-height 1.6):
Syntax tokens (use spans):
- key: `#b6c1d6`
- string: `#c5d99a`
- number: `#f1c075`
- comment: `#6b7281`
- type/built-in: `#a8c5ff`
- punct: `#a4abb8`

Response bodies have a small "RESPONSE 200" ribbon on top using `.code-resp-head`
with `#0f7a3d` "200" pill.

### Status-code badges (`<span class="status status--ok|warn|err">`)
- 200/201 — bg `#e7f6ec` fg `#0f7a3d` (mono 11px weight 600 padding 2/8)
- 400/422/429 — bg `#fdf3d6` fg `#946700`
- 401/403/404/409 — bg `#fdf3d6` fg `#946700`
- 500 — bg `#fbe9e9` fg `#b03333`

### Param list (`<dl class="param-list">`)

Vertical list. For each param:
```
name           string   REQUIRED          ← <dt>: name mono 13 #0f1115, type mono 11 #5d6470, required tag mono 9 weight 700 #b03333 in #fbe9e9 pill
Description text here.                    ← <dd>: 13px #5d6470
```
Stack with 16px gap. No table grid.

### Param row table — used on guides (e.g. error status codes, lifecycle)
Plain HTML table with `<th>` mono 10px uppercase tracking `#9aa0a8`, `<td>`
13px `#0f1115` (mono for codes), row separator border-b `#eaecef`, padding
12/16, no outer borders.

### Numbered step (`<div class="step">`)
Used in Quickstart. Square 28x28 dark `#0f1115` with white digit (Inter 13px
weight 600), then heading right (Inter 14px weight 600 `#0f1115`), then
prose description and code below — indented under the heading, not under
the number column.

### Lifecycle diagram (Quickstart)
SVG of state machine: `pending → running → waiting → running → completed`
with `on error → failed` shown as a dashed red branch. Each state is a
mono pill in a thin gray-bordered rounded rect; `completed` has a green
border. Dashes & arrows in `#9aa0a8`. Use a single inline SVG in the
quickstart partial.

---

## 7. Typography

```
Body          Inter 13px / 1.5    #0f1115
H1 (page)     Inter 28px / 600    #0f1115
H2 (section)  Inter 18px / 600    #0f1115   (margin-top 32, margin-bottom 12)
H3            Inter 14px / 600    #0f1115
Mono          JetBrains Mono 12px (default code), 11–13px in context
```

Inter and JetBrains Mono are already loaded by `layouts/application.html.erb`.
The custom layout must include the same Google Fonts `<link>`.

---

## 8. Color tokens (already in `app/assets/tailwind/application.css`)

| token         | hex      |
|---------------|----------|
| bg            | `#fff`   |
| bg-sunken     | `#f7f8fa`|
| bg-pill       | `#eef0f3`|
| border        | `#eaecef`|
| border-strong | `#d5d8de`|
| fg            | `#0f1115`|
| fg-muted      | `#5d6470`|
| fg-faint      | `#9aa0a8`|
| ok / ok-bg    | `#0f7a3d` / `#e7f6ec` |
| info / info-bg| `#1f4ed8` / `#e3ebfd` |
| warn / warn-bg| `#946700` / `#fdf3d6` |
| err / err-bg  | `#b03333` / `#fbe9e9` |

If the design needs a dark code surface, add `--color-bg-code-dark: #0f1115`
and `--color-border-code: #2a2f3a` to the Tailwind theme — these aren't
present yet (existing `bg-code` is `#f7f8fa` for the light snippets used
elsewhere).

Syntax-highlight color tokens for inline classes (`.tk-key`, `.tk-str`, …)
should be added once in a small CSS file colocated with the api-docs view.

---

## 9. Interactivity

### Stimulus controller: `api-docs--code-tabs`
- Targets: `tab` (each button), `pane` (each pre/code block)
- Action: `click->api-docs--code-tabs#switch`
- On click: set `data-active` on the matching tab, hide other panes via
  `.hidden`. Default-active = first tab (curl).
- Single-controller-per-CodePanel — one panel may have its own tabs
  while another (e.g. RESPONSE-only) renders without tabs.

### Stimulus controller: `api-docs--copy`
- Target: `source` (the `<pre>`)
- Action: `click->api-docs--copy#copy`
- Reads `this.sourceTarget.innerText`, calls `navigator.clipboard.writeText`,
  toggles button label to "Copied" for 1.2s.

### Sidebar nav
- Active link: server-renders the `.on` modifier based on `current_path`.
  No JS toggling.
- Endpoint section toggles? — **No.** All sections always expanded; this
  matches the design.

### Search input
- Pure visual stub. NO submit handler, NO controller. Document the
  intent in a comment so a future agent can hook it up.

---

## 10. Routes

Replace
```ruby
get "/api-docs", to: "api_docs#index", as: :api_docs
```
with
```ruby
scope "/api-docs", as: :api_docs do
  root to: "api_docs#index"                                          # api_docs
  get "guides/:slug",    to: "api_docs#guide",    as: :guide,
      constraints: { slug: /[a-z][a-z0-9_-]*/ }
  get "endpoints/:slug", to: "api_docs#endpoint", as: :endpoint,
      constraints: { slug: /[a-z][a-z0-9_-]*/ }
end
```

`#index` redirects (or renders) Quickstart.

---

## 11. Catalog (single source of truth)

Add `app/services/ui/api_docs/catalog.rb` exposing:
```ruby
module Ui::ApiDocs
  module Catalog
    GUIDES = [
      { slug: "quickstart",      label: "Quickstart" },
      { slug: "authentication",  label: "Authentication" },
      { slug: "process-format",  label: "Process format" },
      { slug: "errors",          label: "Errors" },
      { slug: "versioning",      label: "Versioning" }
    ].freeze

    ENDPOINT_SECTIONS = [
      { key: :discovery, label: "Discovery", endpoints: [
          { slug: "list-processes", method: "GET",  path: "/sop/",                           summary_key: "list_processes" },
          { slug: "process-schema", method: "GET",  path: "/sop/:name/schema",               summary_key: "process_schema" }
        ]},
      { key: :processes, label: "Processes", endpoints: [
          { slug: "register-process", method: "POST", path: "/sop/processes/register",       summary_key: "register_process" }
        ]},
      { key: :instances, label: "Instances", endpoints: [
          { slug: "list-instances", method: "GET",  path: "/sop/instances",                  summary_key: "list_instances" },
          { slug: "start-instance", method: "POST", path: "/sop/:name/start",                summary_key: "start_instance" },
          { slug: "show-instance",  method: "GET",  path: "/sop/:name/:id",                  summary_key: "show_instance"  },
          { slug: "cancel-instance",method: "POST", path: "/sop/:name/:id/cancel",           summary_key: "cancel_instance"}
        ]},
      { key: :steps, label: "Steps", endpoints: [
          { slug: "list-steps",    method: "GET",  path: "/sop/:name/:id/steps",              summary_key: "list_steps"    },
          { slug: "submit-step",   method: "POST", path: "/sop/:name/:id/steps/:step_id/submit", summary_key: "submit_step" },
          { slug: "pending-steps", method: "GET",  path: "/sop/steps/pending",                summary_key: "pending_steps" }
        ]},
      { key: :webhook_triggers, label: "Webhook triggers", endpoints: [
          { slug: "fire-trigger", method: "POST", path: "/sop/triggers/:process_name",       summary_key: "fire_trigger" }
        ]},
      { key: :webhook_callbacks, label: "Webhook callbacks", endpoints: [
          { slug: "deliver-callback", method: "POST", path: "/sop/webhooks/:callback_id",   summary_key: "deliver_callback" }
        ]},
      { key: :metrics, label: "Metrics", endpoints: [
          { slug: "show-metrics", method: "GET", path: "/sop/metrics",                      summary_key: "show_metrics" }
        ]}
    ].freeze

    def self.guide(slug);    GUIDES.find { |g| g[:slug] == slug }; end
    def self.endpoint(slug); ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.find { |e| e[:slug] == slug }; end
  end
end
```

The controller passes the catalog to the sidebar partial each render.

---

## 12. Endpoint page content shape

Each endpoint partial follows:

```
crumbs       (api / <section> / <endpoint label>)
H1           (endpoint label, e.g. "Start an instance")
[METHOD] /path   (with :param highlighted)
prose        (1–2 paragraphs)
callout      (AUTH — Requires X-SOP-Token. See Authentication.)
H2 PATH PARAMETERS    (mono uppercase 11px)
param list
H2 REQUEST BODY       (only for POST)
prose / param list
H2 Response
status row (e.g. 200 application/json — Returns…)
H2 Errors
error rows  (status code badge + code identifier + meaning)
```

Right column (sticky):
- Code panel "Request" — tabs: curl / node / python / ruby
- Code panel "Request body" — only for POST/PATCH bodies
- Code panel "Response" with status pill in header

Right column should `position: sticky; top: 64`, max-height = viewport - top
- 24, scroll-y inside.

For wide screens (≥ 1280) two-column. Below that, stack right column under
the prose with `lg:grid-cols-[1fr_minmax(0,420px)]` etc.

---

## 13. Files to create / modify

**New files:**
```
app/views/layouts/api_docs.html.erb
app/views/ui/api_docs/_topbar.html.erb
app/views/ui/api_docs/_sidebar.html.erb
app/views/ui/api_docs/_page_header.html.erb
app/views/ui/api_docs/_callout.html.erb
app/views/ui/api_docs/_code_panel.html.erb
app/views/ui/api_docs/index.html.erb                  (REPLACE)
app/views/ui/api_docs/guides/_quickstart.html.erb
app/views/ui/api_docs/guides/_authentication.html.erb
app/views/ui/api_docs/guides/_process_format.html.erb
app/views/ui/api_docs/guides/_errors.html.erb
app/views/ui/api_docs/guides/_versioning.html.erb
app/views/ui/api_docs/endpoints/_<each_slug>.html.erb (12 partials)
app/views/ui/api_docs/guide.html.erb                  (renders by slug)
app/views/ui/api_docs/endpoint.html.erb               (renders by slug)
app/services/ui/api_docs/catalog.rb
app/javascript/controllers/api_docs_code_tabs_controller.js
app/javascript/controllers/api_docs_copy_controller.js
spec/requests/ui/api_docs_spec.rb                     (UPDATE — coverage for all routes)
```

**Modify:**
```
app/controllers/ui/api_docs_controller.rb             (add #guide, #endpoint)
config/routes/ui.rb                                   (replace single get)
config/locales/opensop.en.yml                         (full content tree)
app/javascript/controllers/index.js                   (register new controllers)
app/components/sidebar_component.rb                   (no change unless link target changes — but `ui_api_docs_path` should still resolve)
app/assets/tailwind/application.css                   (add minor api-docs scope, if needed)
```

---

## 14. Acceptance — must pass before "done"

1. Visiting `/api-docs` renders the new layout (custom topbar + 240px sidebar,
   no main app sidebar/rail) and shows Quickstart content.
2. Visiting `/api-docs/guides/authentication` shows the Authentication page.
3. Visiting `/api-docs/endpoints/start-instance` shows the Start-an-instance
   endpoint page with right-side dark code panel.
4. Sidebar active state: only the current page has the `.on` style.
5. Code panel tabs (curl/node/python/ruby) switch panes on click.
6. Copy button copies code to clipboard and briefly shows "Copied".
7. Method-badge colors match the spec exactly.
8. The page renders cleanly at 1440 (desktop), and stacks the code panel
   under prose at 1024 and below.
9. `bundle exec rspec spec/requests/ui/api_docs_spec.rb` is green and
   covers: index, every guide route, every endpoint route, an unknown
   slug returns 404.
10. The static-design HTML at the source path and the rendered Rails
    page should be visually indistinguishable when compared screenshot-
    by-screenshot for at least Quickstart, Authentication, and one
    endpoint detail.

---

## 15. Conventions to obey

- Tailwind utilities only — NO inline `style=""`.
- I18n: every visible string under `opensop.api_docs.*`. Use full key
  paths: `t('opensop.api_docs.guides.quickstart.title')`. Use `*_html`
  suffix for keys that contain markup.
- ViewComponent or partial — partials are fine for one-off layout pieces;
  use a ViewComponent only if a piece is reused with different params
  across guides AND endpoints (e.g. CodePanel deserves a component;
  PageHeader is a partial).
- Heroicons for icons — inline SVG, sized 16×16 default.
- Stimulus controller files use kebab-case in `data-controller` (e.g.
  `data-controller="api-docs--code-tabs"`) and snake_case filenames
  (`api_docs_code_tabs_controller.js`).
- All copy lives in i18n. Do not commit hardcoded body text in ERB.
