import { Controller } from "@hotwired/stimulus"

// Tab switcher for the right-hand activity rail. Toggles visibility of
// `[data-activity-rail-target="panel"]` elements based on which tab button
// was clicked. The active tab carries the bottom border + non-faint text.
//
// Usage in markup:
//   <aside data-controller="activity-rail">
//     <div role="tablist">
//       <button data-activity-rail-target="tab"
//               data-activity-rail-key-param="feed"
//               data-action="click->activity-rail#switch">Feed</button>
//       ...
//     </div>
//     <section data-activity-rail-target="panel" data-key="feed">...</section>
//     <section data-activity-rail-target="panel" data-key="agents" hidden>...</section>
//   </aside>
export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const key = event.currentTarget.dataset.activityRailKeyParam
    if (!key) return

    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.activityRailKeyParam === key
      tab.classList.toggle("text-fg", isActive)
      tab.classList.toggle("border-fg", isActive)
      tab.classList.toggle("text-fg-muted", !isActive)
      tab.classList.toggle("border-transparent", !isActive)
      tab.setAttribute("aria-selected", isActive ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      const visible = panel.dataset.key === key
      panel.toggleAttribute("hidden", !visible)
    })
  }
}
