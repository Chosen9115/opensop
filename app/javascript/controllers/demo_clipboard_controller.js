// Stimulus controller: demo-clipboard
// Copies a configured text value to the clipboard. Briefly shows a "Copied"
// label on the trigger button for 1.4s, then reverts.
//
// Values:
//   text — the string to write to the clipboard (set via data-demo-clipboard-text-value)
//
// Targets:
//   label — the <span> inside the Copy button (optional; button text swaps if present)
//
// Action: click->demo-clipboard#copy
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values  = { text: String }
  static targets = ["label"]

  copy() {
    const text = this.textValue || ""

    navigator.clipboard.writeText(text).then(() => {
      if (this.hasLabelTarget) {
        const original = this.labelTarget.textContent
        this.labelTarget.textContent = "Copied"
        setTimeout(() => {
          this.labelTarget.textContent = original
        }, 1400)
      }
    }).catch(() => {
      // Clipboard API not available (e.g. non-secure context) — fail silently.
    })
  }
}
