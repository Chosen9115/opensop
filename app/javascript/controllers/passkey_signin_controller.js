import { Controller } from "@hotwired/stimulus";
import {
  decodeOptionsForGet, credentialToJSON, csrfToken
} from "controllers/base64url";

// Drives the passkey sign-in flow on /auth/sign_in.
//
// Two paths it activates:
//   1. Conditional UI (autofill) — on connect, if PublicKeyCredential.isConditionalMediationAvailable()
//      resolves to true, request options with empty allow list and fire
//      navigator.credentials.get({ mediation: "conditional" }) so the
//      browser can surface passkeys directly in the email field.
//   2. Explicit click — when the "Sign in with passkey" button is pressed,
//      request options for the typed email and fire navigator.credentials.get()
//      modally.
//
// On a successful assertion: POST to /auth/passkey/verify, follow redirect_to.
// On error: surface a toast via the existing `flash` controller.
export default class extends Controller {
  static targets = ["email", "submit", "error"];
  static values = {
    optionsUrl: String,
    verifyUrl: String
  };

  async connect() {
    if (!window.PublicKeyCredential) {
      this.showFallback();
      return;
    }
    if (typeof PublicKeyCredential.isConditionalMediationAvailable === "function") {
      const supported = await PublicKeyCredential.isConditionalMediationAvailable().catch(() => false);
      if (supported) this.startConditional();
    }
  }

  disconnect() {
    this.abortConditional();
  }

  async submit(event) {
    event?.preventDefault?.();
    const email = this.hasEmailTarget ? this.emailTarget.value.trim() : "";
    if (!email) {
      this.showError(this.element.dataset.passkeySigninEmailRequiredText || "Please enter your email.");
      return;
    }
    // Cancel the pending conditional get() so the explicit one doesn't
    // compete with it (Chrome throws InvalidStateError otherwise).
    this.abortConditional();
    await this.runAssertion(email, { mediation: "optional" });
  }

  async startConditional() {
    this._conditionalAbort = new AbortController();
    try {
      await this.runAssertion("", { mediation: "conditional", signal: this._conditionalAbort.signal });
    } catch (e) {
      // Conditional UI failures are silent — user can still click the button.
    }
  }

  abortConditional() {
    if (this._conditionalAbort) {
      try { this._conditionalAbort.abort(); } catch (_) {}
      this._conditionalAbort = null;
    }
  }

  async runAssertion(email, { mediation, signal }) {
    // The conditional flow runs invisibly in the background while the browser
    // waits for the user to engage with the email field's autofill. That promise
    // can stay pending indefinitely, so it must NOT touch user-visible state
    // (button disabled, error toast). Only the explicit click flow disables UI.
    const silent = mediation === "conditional";
    if (!silent) this.setBusy(true);
    try {
      const optionsResponse = await fetch(this.optionsUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" },
        credentials: "same-origin",
        body: new URLSearchParams({ email })
      });
      if (!optionsResponse.ok) throw new Error("options request failed");
      const options = decodeOptionsForGet(await optionsResponse.json());

      const getOptions = {
        publicKey: options,
        mediation: mediation || "optional"
      };
      if (signal) getOptions.signal = signal;

      const credential = await navigator.credentials.get(getOptions);
      if (!credential) throw new Error("no credential returned");

      const verifyResponse = await fetch(this.verifyUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken()
        },
        credentials: "same-origin",
        body: JSON.stringify({
          credential: credentialToJSON(credential),
          return_to: this.returnToParam()
        })
      });
      const data = await verifyResponse.json();
      if (verifyResponse.ok && data.redirect_to) {
        window.location.href = data.redirect_to;
      } else if (!silent) {
        this.showError(this.errorMessageFor(data.error));
      }
    } catch (e) {
      // NotAllowedError = user dismissed; quietly stop without scaring them.
      if (!silent && e?.name !== "NotAllowedError") {
        this.showError(this.element.dataset.passkeySigninGenericErrorText || "Sign-in failed. Try the email link instead.");
      }
    } finally {
      if (!silent) this.setBusy(false);
    }
  }

  returnToParam() {
    const hidden = this.element.querySelector('input[name="return_to"]');
    return hidden && hidden.value ? hidden.value : "";
  }

  setBusy(busy) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = busy;
      this.submitTarget.setAttribute("aria-busy", busy ? "true" : "false");
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message;
      this.errorTarget.classList.remove("hidden");
    }
  }

  showFallback() {
    const fallback = this.element.querySelector("[data-passkey-fallback]");
    if (fallback) fallback.classList.remove("hidden");
    if (this.hasSubmitTarget) this.submitTarget.disabled = true;
  }

  errorMessageFor(code) {
    const map = {
      cloned_credential: "This passkey looks like a clone. Use the email link to recover.",
      unknown_credential: "We don't recognize that passkey. Use the email link instead.",
      verification_failed: "Sign-in failed. Try again or use the email link.",
      invalid_challenge: "This sign-in attempt expired. Please try again."
    };
    return map[code] || (this.element.dataset.passkeySigninGenericErrorText || "Sign-in failed.");
  }
}
