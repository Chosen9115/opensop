import { Controller } from "@hotwired/stimulus"

// Copies prompt text to the clipboard with success/failure visual feedback.
//
// Markup contract:
//   <div data-controller="copy-prompt"
//        data-copy-prompt-text-value="..."
//        data-copy-prompt-revert-ms-value="2000">
//     <button data-action="click->copy-prompt#copy">
//       <span data-copy-prompt-target="defaultIcon">…</span>
//       <span data-copy-prompt-target="successIcon" class="hidden">…</span>
//       <span data-copy-prompt-target="defaultLabel">Copy prompt</span>
//       <span data-copy-prompt-target="successLabel" class="hidden">Copied!</span>
//       <span data-copy-prompt-target="errorLabel" class="hidden">Failed to copy</span>
//     </button>
//   </div>
export default class extends Controller {
  static targets = ["defaultIcon", "successIcon", "defaultLabel", "successLabel", "errorLabel"]
  static values = { text: String, revertMs: { type: Number, default: 2000 } }

  connect() {
    this.revertTimer = null
  }

  disconnect() {
    clearTimeout(this.revertTimer)
  }

  async copy() {
    // Cancel any pending revert so rapid clicks don't conflict
    clearTimeout(this.revertTimer)

    // Reset error state from any previous failed attempt
    this.errorLabelTarget.classList.add("hidden")

    // Guard against browsers/contexts without clipboard API
    if (!navigator.clipboard) {
      this._showError(new Error("navigator.clipboard unavailable"))
      return
    }

    try {
      await navigator.clipboard.writeText(this.textValue)
      this._showSuccess()
    } catch (error) {
      this._showError(error)
    }
  }

  // -- private --

  _showSuccess() {
    this.defaultIconTarget.classList.add("hidden")
    this.defaultLabelTarget.classList.add("hidden")
    this.successIconTarget.classList.remove("hidden")
    this.successLabelTarget.classList.remove("hidden")

    this.revertTimer = setTimeout(() => this._revert(), this.revertMsValue)
  }

  _showError(error) {
    console.warn("[copy-prompt]", error)
    this.defaultIconTarget.classList.add("hidden")
    this.defaultLabelTarget.classList.add("hidden")
    this.errorLabelTarget.classList.remove("hidden")
    // No auto-revert on error — user can click again to retry
  }

  _revert() {
    this.successIconTarget.classList.add("hidden")
    this.successLabelTarget.classList.add("hidden")
    this.defaultIconTarget.classList.remove("hidden")
    this.defaultLabelTarget.classList.remove("hidden")
  }
}
