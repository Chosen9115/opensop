// Stimulus controller: api-docs--code-tabs
// Manages tab switching within a CodePanel component.
//
// Targets:
//   tab  — each tab button element (has data-tab-key attribute)
//   pane — each code pane div (has data-pane-key attribute)
//
// Action: click->api-docs--code-tabs#switch
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "pane"]

  connect() {
    // Ensure the first tab is active on connect (handles server-render state)
    if (this.tabTargets.length > 0) {
      this._activate(this.tabTargets[0].dataset.tabKey)
    }
  }

  switch(event) {
    const key = event.currentTarget.dataset.tabKey
    if (!key) return
    this._activate(key)
  }

  _activate(key) {
    // Update tab buttons
    this.tabTargets.forEach((tab) => {
      const isActive = tab.dataset.tabKey === key
      tab.classList.toggle("bg-[#1a1d24]",  isActive)
      tab.classList.toggle("text-white",     isActive)
      tab.classList.toggle("border-b",       isActive)
      tab.classList.toggle("border-[#1f4ed8]", isActive)
      tab.classList.toggle("text-[#a4abb8]", !isActive)
    })

    // Show/hide panes
    this.paneTargets.forEach((pane) => {
      pane.classList.toggle("hidden", pane.dataset.paneKey !== key)
    })
  }
}
