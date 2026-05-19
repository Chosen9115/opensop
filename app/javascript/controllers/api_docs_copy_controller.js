// Stimulus controller: api-docs--copy
// Copies the innerText of the source target to the clipboard.
// Briefly shows "Copied" on the button label for 1.2s, then reverts.
//
// Targets:
//   source — the <pre> element whose text should be copied
//   label  — the <span> inside the Copy button
//
// Action: click->api-docs--copy#copy
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "label"]

  copy() {
    const text = this.hasSourceTarget ? this.sourceTarget.innerText : ""

    navigator.clipboard.writeText(text).then(() => {
      if (this.hasLabelTarget) {
        const original = this.labelTarget.textContent
        this.labelTarget.textContent = "Copied"
        setTimeout(() => {
          this.labelTarget.textContent = original
        }, 1200)
      }
    }).catch(() => {
      // Clipboard API not available (e.g. non-secure context) — fail silently
    })
  }
}
