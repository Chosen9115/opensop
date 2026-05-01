import { Controller } from "@hotwired/stimulus"

// Focuses the API docs search input on ⌘K / Ctrl+K. The input itself is a
// visual placeholder for now — pressing Enter does nothing yet, since the
// docs site has no search backend wired up.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this._onKey = this._onKey.bind(this)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }

  _onKey(e) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
      e.preventDefault()
      this.inputTarget.focus()
      this.inputTarget.select()
    } else if (e.key === "Escape" && document.activeElement === this.inputTarget) {
      this.inputTarget.blur()
    }
  }
}
