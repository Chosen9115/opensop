import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash messages after a short delay and
// support manual dismissal via the close button.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => this.close(), 4000)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }

  close() {
    if (this.timeout) {
      clearTimeout(this.timeout)
      this.timeout = null
    }
    this.element.classList.add("opacity-0", "transition-opacity", "duration-300")
    setTimeout(() => this.element.remove(), 300)
  }
}
